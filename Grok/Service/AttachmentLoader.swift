//
//  AttachmentLoader.swift
//  Grok
//
//  Created by Tricentric Labs on 02/10/2026.
//

import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers
import Vision

/// Reads an attached file into the plain text the model will see.
///
/// Everything happens locally: the file is validated, decoded and — for an
/// image — run through on-device text recognition, and only the resulting text
/// travels to the Gateway. The three failures the composer has to answer for
/// (too large, corrupted, locked) are distinguished here so the UI can show a
/// sentence or a password sheet rather than a generic error.
nonisolated struct AttachmentLoader {

    /// Hard limit on an attached file — the same one the PDF flow applies.
    static var byteLimit: Int { FileImportLimits.byteLimit }

    static var formattedSizeLimit: String { FileImportLimits.formattedByteLimit }

    /// Upper bound on the characters one attachment contributes to a prompt,
    /// so a long document cannot push the request past the Gateway's payload
    /// limit.
    static let characterLimit = 40_000

    /// Reads a file from disk, or throws the reason it cannot be read.
    ///
    /// `password` is supplied on the second attempt, once the user has
    /// answered the sheet a `passwordProtected` failure raised.
    static func load(url: URL, password: String? = nil) async throws -> ChatAttachment {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let name = url.lastPathComponent
        let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard byteCount <= byteLimit else {
            throw AttachmentError.tooLarge(name: name, byteCount: byteCount)
        }

        guard let kind = kind(of: url) else {
            throw AttachmentError.unsupportedType(name: name)
        }

        switch kind {
        case .text:
            return try loadText(url: url, name: name, byteCount: byteCount)
        case .pdf:
            return try loadPDF(url: url, name: name, byteCount: byteCount, password: password)
        case .image:
            return try await loadImage(url: url, name: name, byteCount: byteCount)
        }
    }

    /// Which of the three accepted kinds a file is, by its declared type and
    /// — for files the system cannot type — its extension.
    static func kind(of url: URL) -> AttachmentKind? {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if type.conforms(to: .pdf) { return .pdf }
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .text) { return .text }
        }

        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "heic", "gif", "tiff", "bmp", "webp": return .image
        case "txt", "md", "markdown", "csv", "json", "log", "rtf", "xml", "yml", "yaml": return .text
        default: return nil
        }
    }

    // MARK: Text

    private static func loadText(url: URL, name: String, byteCount: Int) throws -> ChatAttachment {
        guard let data = try? Data(contentsOf: url) else {
            throw AttachmentError.corrupted(name: name)
        }
        guard let decoded = decode(data) else {
            throw AttachmentError.corrupted(name: name)
        }
        guard !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AttachmentError.empty(name: name)
        }
        return ChatAttachment(
            name: name,
            kind: .text,
            byteCount: byteCount,
            text: truncated(decoded)
        )
    }

    /// Decodes with the file's own encoding where one is declared, then the
    /// encodings plain text actually arrives in. A file that answers to none
    /// of them, or that is full of NUL bytes, is binary wearing a .txt
    /// extension — corrupted, as far as the composer is concerned.
    private static func decode(_ data: Data) -> String? {
        let candidates: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .isoLatin1, .windowsCP1252]
        for encoding in candidates {
            guard let text = String(data: data, encoding: encoding), !text.isEmpty else { continue }
            let nulCount = text.unicodeScalars.prefix(4096).filter { $0.value == 0 }.count
            guard nulCount < 8 else { return nil }
            return text
        }
        return nil
    }

    // MARK: PDF

    private static func loadPDF(
        url: URL,
        name: String,
        byteCount: Int,
        password: String?
    ) throws -> ChatAttachment {
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

        // A document that opens but has no pages is damaged rather than empty.
        guard document.pageCount > 0 else {
            throw AttachmentError.corrupted(name: name)
        }

        var text = ""
        for index in 0..<document.pageCount {
            let page = document.page(at: index)?.string ?? ""
            let marked = "[page \(index + 1)]\n\(page)\n"
            guard text.count + marked.count <= characterLimit else { break }
            text += marked
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AttachmentError.empty(name: name)
        }

        return ChatAttachment(
            name: name,
            kind: .pdf,
            byteCount: byteCount,
            text: text,
            pageCount: document.pageCount
        )
    }

    // MARK: Image

    private static func loadImage(url: URL, name: String, byteCount: Int) async throws -> ChatAttachment {
        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            throw AttachmentError.corrupted(name: name)
        }

        // The Gateway's chat endpoint takes text, so an image reaches the model
        // as the text recognized on it plus its dimensions. That is enough for
        // the answer to be about the picture the user attached.
        let recognized = recognizeText(in: cgImage)
        let description = describe(
            width: cgImage.width,
            height: cgImage.height,
            recognized: recognized
        )

        return ChatAttachment(
            name: name,
            kind: .image,
            byteCount: byteCount,
            text: truncated(description),
            previewData: thumbnail(from: cgImage)
        )
    }

    private static func recognizeText(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return ""
        }

        let observations = request.results ?? []
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    private static func describe(width: Int, height: Int, recognized: String) -> String {
        let header = "Image dimensions: \(width)×\(height) pixels."
        guard !recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "\(header)\nNo text could be recognized in this image."
        }
        return "\(header)\nText recognized in the image:\n\(recognized)"
    }

    /// A small PNG for the chip, so the composer never holds a full-size image.
    private static func thumbnail(from image: CGImage, maxEdge: CGFloat = 160) -> Data? {
        let scale = min(maxEdge / CGFloat(image.width), maxEdge / CGFloat(image.height), 1)
        let size = NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)

        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))

        guard let scaled = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
    }

    // MARK: Helpers

    private static func truncated(_ text: String) -> String {
        guard text.count > characterLimit else { return text }
        return String(text.prefix(characterLimit)) + "\n[truncated]"
    }
}
