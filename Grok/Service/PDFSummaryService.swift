//
//  PDFSummaryService.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import Foundation
import PDFKit
import os

/// Failures particular to summarizing. Everything the file itself can be wrong
/// about — too large, corrupted, locked — is reported as an `AttachmentError`,
/// so the PDF screen and the chat composer say the same thing.
nonisolated enum PDFImportError: LocalizedError {
    case unreadable
    case noExtractableText

    var errorDescription: String? {
        switch self {
        case .unreadable: return "This file could not be opened."
        case .noExtractableText: return "This PDF has no selectable text, so it can’t be summarized."
        }
    }
}

nonisolated protocol PDFSummarizing {
    /// Reads a PDF and reports progress as pages are consumed.
    func summarize(
        _ info: PDFDocumentInfo,
        length: SummaryLength,
        onProgress: @escaping (Int) -> Void
    ) async throws -> PDFSummary
}

/// Reads the document with PDFKit, then summarizes its text through the
/// Central AI Gateway.
///
/// Extraction stays local — only the document's text is sent, and only when
/// the user asks for a summary. If the model's reply cannot be read, the
/// service falls back to the local extractive summary so the screen still
/// fills rather than failing.
nonisolated struct PDFSummaryService: PDFSummarizing {

    /// Upper bound on the characters sent in one request, to stay inside the
    /// Gateway's accepted payload size on long documents.
    private static let characterLimit = 60_000

    private let client: GatewayClient

    init(client: GatewayClient = .shared) {
        self.client = client
    }

    /// Reads a file from disk into the model the file row renders, applying the
    /// same rules a chat attachment is held to: five megabytes, a named
    /// corruption failure, and a password prompt for a locked document.
    ///
    /// `password` arrives on the second attempt, once the unlock sheet has been
    /// answered.
    static func inspect(url: URL, password: String? = nil) throws -> PDFDocumentInfo {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let name = url.lastPathComponent

        guard url.pathExtension.lowercased() == "pdf" else {
            throw AttachmentError.unsupportedType(name: name)
        }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= FileImportLimits.byteLimit else {
            throw AttachmentError.tooLarge(name: name, byteCount: size)
        }

        guard let document = PDFDocument(url: url) else {
            throw AttachmentError.corrupted(name: name)
        }

        if document.isLocked {
            guard let password, !password.isEmpty else {
                throw AttachmentError.passwordProtected(name: name)
            }
            guard document.unlock(withPassword: password) else {
                throw AttachmentError.incorrectPassword
            }
        }

        // A file that opens but holds no pages is damaged rather than empty.
        guard document.pageCount > 0 else {
            throw AttachmentError.corrupted(name: name)
        }

        return PDFDocumentInfo(
            url: url,
            name: name,
            pageCount: document.pageCount,
            byteCount: size,
            password: password
        )
    }

    func summarize(
        _ info: PDFDocumentInfo,
        length: SummaryLength,
        onProgress: @escaping (Int) -> Void
    ) async throws -> PDFSummary {
        let scoped = info.url.startAccessingSecurityScopedResource()
        defer { if scoped { info.url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: info.url) else {
            throw AttachmentError.corrupted(name: info.name)
        }

        // Reopening the file re-locks it, so the password the sheet collected
        // is applied again here.
        if document.isLocked {
            guard let password = info.password, document.unlock(withPassword: password) else {
                throw AttachmentError.passwordProtected(name: info.name)
            }
        }

        var pageTexts: [String] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            pageTexts.append(document.page(at: index)?.string ?? "")
            onProgress(index + 1)
            // Paced so the progress bar reads as real work on small documents.
            try await Task.sleep(nanoseconds: 90_000_000)
        }

        let body = pageTexts.joined(separator: "\n")
        let sentences = Self.sentences(in: body)
        guard sentences.count >= 2 else { throw PDFImportError.noExtractableText }

        let fallback = Self.localSummary(
            pageTexts: pageTexts,
            sentences: sentences,
            length: length,
            fileName: info.name
        )

        do {
            return try await summarizeWithGateway(pageTexts: pageTexts, length: length)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GatewayError {
            // Budget, subscription and credential failures are the user's to
            // see; a transient one still yields a usable local summary.
            guard error.isRetryable else { throw error }
            GatewayError.log.notice("Falling back to local PDF summary after a recoverable Gateway error.")
            return fallback
        } catch {
            GatewayError.log.notice("Falling back to local PDF summary: model output was unreadable.")
            return fallback
        }
    }

    // MARK: Gateway

    private func summarizeWithGateway(pageTexts: [String], length: SummaryLength) async throws -> PDFSummary {
        let response = try await client.chat(
            messages: [GatewayChatTurn(role: .user, content: Self.prompt(for: pageTexts))],
            system: Self.systemPrompt(for: length),
            maxOutputTokens: 4096,
            temperature: 0.2
        )
        try Task.checkCancellation()

        let payload = try Self.json(in: response.message.content)
        return PDFSummary(
            title: payload.title,
            overview: payload.overview,
            keyPoints: payload.keyPoints,
            sections: payload.sections.map { SummarySection(title: $0.title, page: $0.page) }
        )
    }

    private static func systemPrompt(for length: SummaryLength) -> String {
        """
        You summarize PDF documents. Reply with JSON only, no code fence and no \
        commentary, matching exactly:
        {"title": string, "overview": string, "key_points": [string], \
        "sections": [{"title": string, "page": number}]}
        The overview is \(length.overviewSentences) sentences of plain prose. \
        Provide \(length.keyPointLimit) key points, each one specific sentence \
        drawn from the document. List up to 6 important sections with the page \
        number each begins on. Use only what the document states.
        """
    }

    private static func prompt(for pageTexts: [String]) -> String {
        var text = ""
        for (index, page) in pageTexts.enumerated() {
            let marked = "[page \(index + 1)]\n\(page)\n"
            guard text.count + marked.count <= characterLimit else { break }
            text += marked
        }
        return "Summarize this document.\n\n\(text)"
    }

    /// Pulls the JSON object out of the reply, tolerating a code fence or a
    /// stray sentence around it.
    private static func json(in reply: String) throws -> SummaryPayload {
        guard let start = reply.firstIndex(of: "{"),
              let end = reply.lastIndex(of: "}"),
              start < end,
              let data = String(reply[start...end]).data(using: .utf8)
        else {
            throw PDFImportError.unreadable
        }
        return try JSONDecoder().decode(SummaryPayload.self, from: data)
    }

    private struct SummaryPayload: Decodable {
        struct Section: Decodable {
            let title: String
            let page: Int
        }

        let title: String
        let overview: String
        let keyPoints: [String]
        let sections: [Section]

        private enum CodingKeys: String, CodingKey {
            case title, overview, sections
            case keyPoints = "key_points"
        }
    }

    // MARK: Local fallback

    private static func localSummary(
        pageTexts: [String],
        sentences: [String],
        length: SummaryLength,
        fileName: String
    ) -> PDFSummary {
        PDFSummary(
            title: title(from: pageTexts.first ?? "", fallback: fileName),
            overview: overview(from: sentences, length: length),
            keyPoints: keyPoints(from: sentences, limit: length.keyPointLimit),
            sections: sections(in: pageTexts)
        )
    }

    // MARK: Extraction

    private static func sentences(in text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.split(separator: " ").count >= 6 }
            .map { $0 + "." }
    }

    private static func title(from firstPage: String, fallback: String) -> String {
        let candidate = firstPage
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.count > 3 && $0.count < 80 }

        return candidate ?? (fallback as NSString).deletingPathExtension
    }

    private static func overview(from sentences: [String], length: SummaryLength) -> String {
        sentences.prefix(length.overviewSentences).joined(separator: " ")
    }

    /// Ranks sentences by how many of the document's frequent words they carry
    /// — a classic extractive summary, and enough to be genuinely useful.
    private static func keyPoints(from sentences: [String], limit: Int) -> [String] {
        var frequencies: [String: Int] = [:]
        for sentence in sentences {
            for word in sentence.lowercased().split(whereSeparator: { !$0.isLetter }) where word.count > 4 {
                frequencies[String(word), default: 0] += 1
            }
        }

        let ranked = sentences.enumerated()
            .map { index, sentence -> (Int, String, Double) in
                let words = sentence.lowercased().split(whereSeparator: { !$0.isLetter })
                let score = words.reduce(0.0) { $0 + Double(frequencies[String($1)] ?? 0) }
                return (index, sentence, score / Double(max(words.count, 1)))
            }
            .sorted { $0.2 > $1.2 }
            .prefix(limit)
            .sorted { $0.0 < $1.0 }

        return ranked.map(\.1)
    }

    /// Lines that read like headings — short, no terminal punctuation — paired
    /// with the page they appear on.
    private static func sections(in pageTexts: [String]) -> [SummarySection] {
        var found: [SummarySection] = []
        for (index, page) in pageTexts.enumerated() {
            for rawLine in page.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                let words = line.split(separator: " ")
                let looksLikeHeading = (2...8).contains(words.count)
                    && line.count < 60
                    && !line.hasSuffix(".")
                    && line.first?.isUppercase == true

                if looksLikeHeading, !found.contains(where: { $0.title == line }) {
                    found.append(SummarySection(title: line, page: index + 1))
                }
                if found.count >= 6 { return found }
            }
        }
        return found
    }
}

nonisolated extension SummaryLength {
    var overviewSentences: Int {
        switch self {
        case .brief: return 2
        case .standard: return 4
        case .detailed: return 7
        }
    }

    var keyPointLimit: Int {
        switch self {
        case .brief: return 3
        case .standard: return 4
        case .detailed: return 6
        }
    }
}
