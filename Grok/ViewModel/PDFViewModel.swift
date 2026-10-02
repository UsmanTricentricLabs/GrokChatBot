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

    private let service: PDFSummarizing
    private let chatService: ChatService
    private var summaryTask: Task<Void, Never>?
    private var followUpTask: Task<Void, Never>?

    init(service: PDFSummarizing = PDFSummaryService(), chatService: ChatService = GatewayChatService()) {
        self.service = service
        self.chatService = chatService
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
        return "Reading page \(max(pagesRead, 1)) of \(info.pageCount)…"
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
        panel.message = "Choose a PDF of up to \(FileImportLimits.formattedByteLimit)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func removeDocument() {
        summaryTask?.cancel()
        followUpTask?.cancel()
        followUps.removeAll()
        followUpDraft = ""
        passwordRequest = nil
        state = .empty
        pagesRead = 0
    }

    // MARK: Summarizing

    func summarize() {
        guard case .selected(let info) = state else { return }
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

    func startNewDocument() {
        removeDocument()
        chooseFile()
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
        guard !question.isEmpty, summary != nil else { return }
        followUpDraft = ""

        followUps.append(ChatMessage(role: .user, text: question))
        let answer = ChatMessage(role: .assistant, blocks: [], state: .thinking)
        followUps.append(answer)

        followUpTask?.cancel()
        followUpTask = Task { [chatService] in
            do {
                for try await snapshot in chatService.respond(to: question) {
                    guard !Task.isCancelled else { return }
                    update(answer.id) {
                        $0.blocks = snapshot
                        $0.state = .streaming
                    }
                }
                update(answer.id) { $0.state = .complete }
            } catch {
                update(answer.id) { $0.state = .failed(AIErrorPresentation(error)) }
            }
        }
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
