//
//  PDFViewModel.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
internal import Combine

/// Drives the PDF Summary flow: drop zone, file row, processing and the
/// finished summary with follow-up questions.
@MainActor
final class PDFViewModel: ObservableObject {

    @Published private(set) var state: PDFFlowState = .empty
    @Published var length: SummaryLength = .standard
    @Published var followUpDraft: String = ""
    @Published private(set) var pagesRead: Int = 0
    @Published private(set) var summarizedDocuments: [PDFDocumentInfo] = []

    /// Questions asked about the open document, answered in place below the
    /// summary.
    @Published private(set) var followUps: [ChatMessage] = []

    /// Set when a locked PDF needs a password before it can be opened.
    @Published var passwordRequest: PasswordRequest?

    /// A locked document waiting on the unlock sheet.
    nonisolated struct PasswordRequest: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let name: String
        /// Set after a wrong password, so the sheet can say so and stay open.
        var errorMessage: String?
        var isUnlocking: Bool = false
    }

    /// Finished summaries, kept so a document picked from the sidebar opens
    /// its own summary again instead of being re-read. Keyed by file, because
    /// re-opening the same PDF describes it with a fresh `PDFDocumentInfo`.
    private var summaries: [URL: PDFSummary] = [:]
    /// The questions asked about each document, restored with its summary.
    private var followUpHistory: [URL: [ChatMessage]] = [:]
    /// Extracted text per document, so the questions asked about one do not
    /// re-read the file each time.
    private var documentTexts: [URL: String] = [:]

    private let service: PDFSummarizing
    private let chatService: ChatService
    private let history: DocumentHistoryStore
    private var historyObserver: AnyCancellable?
    private var summaryTask: Task<Void, Never>?
    private var followUpTask: Task<Void, Never>?

    init(
        service: PDFSummarizing = PDFSummaryService(),
        chatService: ChatService = GatewayChatService(),
        history: DocumentHistoryStore = .shared
    ) {
        self.service = service
        self.chatService = chatService
        self.history = history

        // The flow always opens on the drop zone, with the documents read
        // before it waiting in the sidebar — summary and questions included.
        let stored = history.load()
        summarizedDocuments = stored.map(\.info)
        for document in stored {
            summaries[document.info.url] = document.summary
            followUpHistory[document.info.url] = document.followUps
        }

        // A new summary, or an answer to a question about one, is written out
        // once it settles rather than on every streamed chunk.
        historyObserver = Publishers.Merge(
            $summarizedDocuments.map { _ in () },
            $followUps.map { _ in () }
        )
        .dropFirst()
        .debounce(for: .seconds(0.4), scheduler: RunLoop.main)
        .sink { [weak self] in
            self?.persistHistory()
        }
        _ = terminationObserver
    }

    /// Quitting does not wait for the debounce, so the last summary and the
    /// last answer are written on the way out.
    private lazy var terminationObserver: Any = NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        MainActor.assumeIsolated { self?.persistHistory() }
    }

    /// Writes the sidebar list out with each document's summary and the
    /// questions asked about it.
    func persistHistory() {
        stashFollowUps()

        let records = summarizedDocuments.compactMap { info -> SummarizedDocument? in
            guard let summary = summaries[info.url] else { return nil }
            return SummarizedDocument(
                info: info,
                summary: summary,
                followUps: Self.storable(followUpHistory[info.url] ?? [])
            )
        }
        history.save(records)
    }

    /// A question whose answer never arrived would come back as a spinner, so
    /// the thread is cut at the last finished exchange.
    private static func storable(_ messages: [ChatMessage]) -> [ChatMessage] {
        var storable = messages.filter { $0.role == .user || $0.state == .complete }
        if storable.last?.role == .user { storable.removeLast() }
        return storable
    }

    // MARK: Derived state

    var document: PDFDocumentInfo? {
        switch state {
        case .selected(let info), .processing(let info), .summarized(let info, _): return info
        default: return nil
        }
    }

    var summary: PDFSummary? {
        if case .summarized(_, let summary) = state { return summary }
        return nil
    }

    /// The reading progress shown by the thin bar, 0…1.
    var progress: Double {
        guard case .processing(let info) = state, info.pageCount > 0 else { return 0 }
        return Double(pagesRead) / Double(info.pageCount)
    }

    var progressLabel: String {
        guard case .processing(let info) = state else { return "" }
        return "pdf.readingPage".localized(max(pagesRead, 1), info.pageCount)
    }

    /// The hero and drop zone show only while no summary exists.
    var showsHero: Bool {
        switch state {
        case .processing, .summarized: return false
        default: return true
        }
    }

    // MARK: Drag & drop

    func setDragging(_ isDragging: Bool, fileName: String? = nil) {
        switch state {
        case .empty, .dragging, .failed:
            state = isDragging ? .dragging(fileName: fileName) : .empty
        default:
            break
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) })
        else {
            state = .empty
            return false
        }

        _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
            let droppedURL = url
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let droppedURL else {
                    self.state = .empty
                    return
                }
                // Everything else — the size, a damaged file, a locked one —
                // is decided by `open`, so a drop and a pick behave alike.
                self.open(droppedURL)
            }
        }
        return true
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "pdf.choosePrompt".localized(FileImportLimits.formattedByteLimit)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func removeDocument() {
        summaryTask?.cancel()
        followUpTask?.cancel()
        stashFollowUps()
        followUps.removeAll()
        followUpDraft = ""
        passwordRequest = nil
        state = .empty
        pagesRead = 0
    }

    // MARK: Summarizing

    func summarize() {
        guard case .selected(let info) = state else { return }
        guard PaywallPresenter.shared.claimRun() else { return }

        pagesRead = 0
        state = .processing(info)

        summaryTask?.cancel()
        summaryTask = Task { [service, length] in
            do {
                let summary = try await service.summarize(info, length: length) { page in
                    Task { @MainActor in self.pagesRead = page }
                }
                guard !Task.isCancelled else { return }
                state = .summarized(info, summary)
                summaries[info.url] = summary
                if !summarizedDocuments.contains(where: { $0.url == info.url }) {
                    summarizedDocuments.insert(info, at: 0)
                }
            } catch is CancellationError {
                state = .selected(info)
            } catch let error as AttachmentError {
                state = .failed(fileName: info.name, reason: error.rowDetail)
            } catch {
                state = .failed(fileName: info.name, reason: error.localizedDescription)
            }
        }
    }

    func cancelSummarizing() {
        summaryTask?.cancel()
        summaryTask = nil
        if case .processing(let info) = state {
            state = .selected(info)
        }
        pagesRead = 0
    }

    /// Opens a document from the sidebar list again, with the summary it
    /// already produced and the questions asked about it.
    func select(_ info: PDFDocumentInfo) {
        guard info.url != document?.url else { return }

        summaryTask?.cancel()
        followUpTask?.cancel()
        stashFollowUps()

        followUpDraft = ""
        passwordRequest = nil
        pagesRead = 0
        followUps = followUpHistory[info.url] ?? []

        // A document only reaches the list once it has a summary, so the
        // stored one is what reopening shows; without it the file is simply
        // offered for summarizing again.
        if let summary = summaries[info.url] {
            state = .summarized(info, summary)
        } else {
            state = .selected(info)
        }
    }

    /// Deletes a summarized document from the sidebar list, along with the
    /// summary and the questions asked about it.
    ///
    /// Deleting the document that is currently open also clears the screen,
    /// since leaving a summary on display for a document no longer in the list
    /// is a state the user cannot get back to.
    func delete(_ info: PDFDocumentInfo) {
        if info.url == document?.url {
            removeDocument()
        }

        summarizedDocuments.removeAll { $0.url == info.url }
        summaries[info.url] = nil
        followUpHistory[info.url] = nil
    }

    /// Keeps the open document's questions, so stepping away and back does not
    /// lose them.
    private func stashFollowUps() {
        guard let current = document else { return }
        followUpHistory[current.url] = followUps
    }

    /// The summary screen's own "New" button: clear the open document and go
    /// straight to the file picker.
    func startNewDocument() {
        removeDocument()
        chooseFile()
    }

    /// Entering the flow from the sidebar, which lands on the empty drop zone
    /// rather than on the last summary — the same fresh start New Chat and
    /// Create Image give. Summarized documents stay in the sidebar list.
    func startNewSummary() {
        removeDocument()
    }

    // MARK: Follow-up questions

    var canAskFollowUp: Bool {
        !followUpDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isAnsweringFollowUp: Bool {
        followUps.contains { $0.role == .assistant && $0.isAwaitingResponse }
    }

    func askFollowUp() {
        let question = followUpDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, let summary, let info = document else { return }
        guard PaywallPresenter.shared.claimRun() else { return }

        followUpDraft = ""

        followUps.append(ChatMessage(role: .user, text: question))
        beginFollowUp(to: question, summary: summary, document: info)
    }

    /// Replaces the last answer with a freshly generated one, from the
    /// question that produced it.
    func regenerateLastFollowUp() {
        guard let summary, let info = document else { return }
        guard let answerIndex = followUps.lastIndex(where: { $0.role == .assistant }),
              let question = followUps[..<answerIndex].last(where: { $0.role == .user })?.modelText
        else { return }
        guard PaywallPresenter.shared.claimRun() else { return }

        // The answer goes, the question it answered stays: it is asked again
        // exactly as it was.
        followUps.removeSubrange(answerIndex...)
        beginFollowUp(to: question, summary: summary, document: info)
    }

    /// Recovery action on the error row.
    func retryLastFollowUp() {
        regenerateLastFollowUp()
    }

    private func beginFollowUp(to question: String, summary: PDFSummary, document info: PDFDocumentInfo) {
        // The turns before this question, so the model sees the conversation
        // as it was asked — the question itself travels as the prompt.
        let earlier = Array(followUps.dropLast())
        let answer = ChatMessage(role: .assistant, blocks: [], state: .thinking)
        followUps.append(answer)

        followUpTask?.cancel()
        followUpTask = Task { [chatService] in
            do {
                // The document travels with the question: the Gateway keeps
                // nothing between calls, so a question asked on its own would
                // reach a model that has never seen the PDF.
                let system = await documentContext(for: info, summary: summary)
                try Task.checkCancellation()

                for try await snapshot in chatService.respond(to: question, history: earlier, system: system) {
                    guard !Task.isCancelled else { return }
                    update(answer.id) {
                        $0.blocks = snapshot
                        $0.state = .streaming
                    }
                }
                update(answer.id) { $0.state = .complete }
            } catch is CancellationError {
                return
            } catch {
                update(answer.id) { $0.state = .failed(AIErrorPresentation(error)) }
            }
        }
    }

    /// The system prompt a follow-up is answered under: who the model is
    /// answering for, and the document it has to answer from.
    ///
    /// The text is read once per document and kept, because a question is
    /// asked far more often than a file is opened. Should the file no longer
    /// be readable — moved, or its security scope gone — the summary stands in
    /// for it, which is still the document in the user's words.
    private func documentContext(for info: PDFDocumentInfo, summary: PDFSummary) async -> String {
        let body: String

        if let cached = documentTexts[info.url] {
            body = cached
        } else if let text = await Task.detached(priority: .userInitiated, operation: {
            PDFSummaryService.pageMarkedText(for: info)
        }).value {
            documentTexts[info.url] = text
            body = text
        } else {
            body = summary.plainText
        }

        return """
            You are Grok, answering questions about one PDF the user has open: \
            "\(info.name)", \(info.pageCount) page(s). Its text follows, with a \
            marker before each page. Answer only from that text, cite the page \
            when it helps, and say plainly when the document does not cover \
            what was asked — never ask the user to attach or paste the file, \
            because it is already here. Answer in clear prose with short \
            paragraphs, using Markdown when it helps. Do not use emoji.

            DOCUMENT
            \(body)
            """
    }

    func stopFollowUp() {
        followUpTask?.cancel()
        followUpTask = nil
        guard let last = followUps.indices.last, followUps[last].isAwaitingResponse else { return }

        if followUps[last].text.isEmpty {
            followUps.removeLast()
        } else {
            followUps[last].state = .complete
        }
    }

    func copy(_ message: ChatMessage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
    }

    func speak(_ message: ChatMessage) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            return
        }
        synthesizer.speak(AVSpeechUtterance(string: message.text))
    }

    private func update(_ messageID: UUID, _ body: (inout ChatMessage) -> Void) {
        guard let index = followUps.firstIndex(where: { $0.id == messageID }) else { return }
        body(&followUps[index])
    }

    private let synthesizer = AVSpeechSynthesizer()

    // MARK: Summary actions

    func copySummary() {
        guard let summary else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary.plainText, forType: .string)
    }

    func share(from view: NSView?) {
        guard let view, let summary else { return }
        NSSharingServicePicker(items: [summary.plainText]).show(
            relativeTo: .zero,
            of: view,
            preferredEdge: .minY
        )
    }

    /// Opens a document, whether it arrived by drop or from the open panel.
    ///
    /// The same three rules the chat composer applies are applied here: five
    /// megabytes, a named failure for a corrupted file, and the unlock sheet —
    /// not an error — for a password-protected one.
    func open(_ url: URL, password: String? = nil) {
        followUpTask?.cancel()
        stashFollowUps()
        followUps.removeAll()
        followUpDraft = ""

        do {
            state = .selected(try PDFSummaryService.inspect(url: url, password: password))
            passwordRequest = nil
        } catch let error as AttachmentError {
            if let name = error.lockedFileName {
                state = .empty
                passwordRequest = PasswordRequest(url: url, name: name)
                return
            }
            state = .failed(fileName: url.lastPathComponent, reason: error.rowDetail)
        } catch {
            state = .failed(fileName: url.lastPathComponent, reason: error.localizedDescription)
        }
    }

    // MARK: Unlocking

    /// The unlock sheet's primary button. A wrong password keeps the sheet
    /// open so the next attempt needs no re-picking of the file.
    func submitPassword(_ password: String) {
        guard var request = passwordRequest, !request.isUnlocking else { return }

        do {
            let info = try PDFSummaryService.inspect(url: request.url, password: password)
            passwordRequest = nil
            state = .selected(info)
        } catch AttachmentError.incorrectPassword {
            request.errorMessage = AttachmentError.incorrectPassword.errorDescription
            request.isUnlocking = false
            passwordRequest = request
        } catch let error as AttachmentError {
            passwordRequest = nil
            state = .failed(fileName: request.name, reason: error.rowDetail)
        } catch {
            passwordRequest = nil
            state = .failed(fileName: request.name, reason: error.localizedDescription)
        }
    }

    func cancelPasswordRequest() {
        passwordRequest = nil
        state = .empty
    }
}
