//
//  ChatViewModel.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
internal import Combine

/// Drives the Chat flow: the conversation list in the sidebar and the
/// thread, streaming and error states in the main column.
@MainActor
final class ChatViewModel: ObservableObject {

    @Published private(set) var conversations: [Conversation]
    @Published var selectedConversationID: UUID?
    @Published var draft: String = ""

    /// Sidebar history search.
    @Published var isSearching: Bool = false
    @Published var searchQuery: String = ""

    // MARK: Attachments

    /// Files staged for the next prompt.
    @Published private(set) var attachments: [ChatAttachment] = []
    /// Why the last file could not be attached, as the banner shows it.
    @Published var attachmentError: String?
    /// True while a chosen file is being read.
    @Published private(set) var isReadingAttachment = false
    /// Set when a locked PDF needs a password before it can be attached.
    @Published var passwordRequest: PasswordRequest?

    /// At most this many files travel with one prompt.
    static let attachmentLimit = 5

    /// A locked PDF waiting on the password sheet.
    nonisolated struct PasswordRequest: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let name: String
        /// Queued files that follow this one once it is resolved.
        let remaining: [URL]
        /// Set after a wrong password, so the sheet can say so and stay open.
        var errorMessage: String?
        var isUnlocking: Bool = false
    }

    private let service: ChatService
    private var responseTask: Task<Void, Never>?

    init(service: ChatService = GatewayChatService()) {
        self.service = service
        self.conversations = ChatViewModel.recentHistory
    }

    // MARK: Derived state

    var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedConversationID }
    }

    var messages: [ChatMessage] {
        selectedConversation?.messages ?? []
    }

    /// True while an answer is being produced, which turns Send into Stop.
    var isResponding: Bool {
        messages.contains { $0.role == .assistant && $0.isAwaitingResponse }
    }

    /// A prompt can go as soon as there is something to send — typed text, an
    /// attached file, or both.
    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    /// The history as the sidebar shows it: pinned first, then most recent,
    /// filtered by the search field when it is open.
    var visibleConversations: [Conversation] {
        let ordered = conversations.sorted {
            $0.isPinned == $1.isPinned ? $0.updatedAt > $1.updatedAt : $0.isPinned
        }
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard isSearching, !query.isEmpty else { return ordered }
        return ordered.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    // MARK: Conversation management

    func startNewConversation() {
        cancelResponse()
        selectedConversationID = nil
        draft = ""
        clearAttachments()
    }

    func select(_ conversation: Conversation) {
        cancelResponse()
        selectedConversationID = conversation.id
        clearAttachments()
    }

    func rename(_ conversation: Conversation, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = index(of: conversation.id) else { return }
        conversations[index].title = trimmed
    }

    func togglePin(_ conversation: Conversation) {
        guard let index = index(of: conversation.id) else { return }
        conversations[index].isPinned.toggle()
    }

    func delete(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        if selectedConversationID == conversation.id {
            startNewConversation()
        }
    }

    func share(_ conversation: Conversation) {
        copyToPasteboard(
            conversation.messages
                .map { "\($0.role == .user ? "You" : "Grok"): \($0.text)" }
                .joined(separator: "\n\n")
        )
    }

    func toggleSearch() {
        isSearching.toggle()
        if !isSearching { searchQuery = "" }
    }

    // MARK: Sending

    func send() {
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let sent = attachments
        guard !typed.isEmpty || !sent.isEmpty else { return }

        // Attaching a file without typing anything is a request to read it.
        let prompt = typed.isEmpty ? Self.defaultAttachmentPrompt(for: sent) : typed

        draft = ""
        clearAttachments()

        let conversationID = selectedConversationID ?? openConversation(titledFrom: prompt)
        guard let index = index(of: conversationID) else { return }

        let message = ChatMessage(role: .user, text: prompt, attachments: sent)
        conversations[index].messages.append(message)
        conversations[index].updatedAt = Date()
        beginResponse(to: message.modelText, in: conversationID)
    }

    func stop() {
        cancelResponse()
        guard let index = index(of: selectedConversationID),
              let last = conversations[index].messages.indices.last,
              conversations[index].messages[last].isAwaitingResponse else { return }

        if conversations[index].messages[last].text.isEmpty {
            conversations[index].messages.removeLast()
        } else {
            conversations[index].messages[last].state = .complete
        }
    }

    /// Replaces the last answer with a freshly generated one.
    func regenerateLastResponse() {
        guard let index = index(of: selectedConversationID) else { return }
        guard let answerIndex = conversations[index].messages.lastIndex(where: { $0.role == .assistant }),
              let prompt = conversations[index].messages[..<answerIndex].last(where: { $0.role == .user })?.modelText
        else { return }

        conversations[index].messages.removeSubrange(answerIndex...)
        beginResponse(to: prompt, in: conversations[index].id)
    }

    /// Recovery action on the error row.
    func retryLastResponse() {
        regenerateLastResponse()
    }

    func copy(_ message: ChatMessage) {
        copyToPasteboard(message.text)
    }

    /// Read Aloud. Speaking again while a message is playing stops it, which
    /// matches how the control behaves elsewhere on the system.
    func speak(_ message: ChatMessage) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            return
        }
        synthesizer.speak(AVSpeechUtterance(string: message.text))
    }

    private let synthesizer = AVSpeechSynthesizer()

    // MARK: Attachments

    /// The attach button: one panel that takes the three kinds the chat can
    /// read — a text file, a PDF or an image.
    func chooseAttachments() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = AttachmentKind.acceptedContentTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Attach"
        panel.message = "Attach a text file, PDF or image (up to \(AttachmentLoader.formattedSizeLimit) each)."
        guard panel.runModal() == .OK else { return }
        attach(panel.urls)
    }

    /// Reads and stages files, whether they were chosen or dropped on the bar.
    func attach(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        attachmentError = nil
        Task { await load(urls) }
    }

    func removeAttachment(_ attachment: ChatAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    func clearAttachments() {
        attachments.removeAll()
        attachmentError = nil
        passwordRequest = nil
    }

    /// The password sheet's Unlock button.
    func submitPassword(_ password: String) {
        guard var request = passwordRequest, !request.isUnlocking else { return }
        request.isUnlocking = true
        request.errorMessage = nil
        passwordRequest = request

        Task {
            do {
                let attachment = try await AttachmentLoader.load(url: request.url, password: password)
                stage(attachment)
                passwordRequest = nil
                await load(request.remaining)
            } catch let error as AttachmentError where error == .incorrectPassword {
                var retry = request
                retry.isUnlocking = false
                retry.errorMessage = error.errorDescription
                passwordRequest = retry
            } catch {
                passwordRequest = nil
                report(error)
                await load(request.remaining)
            }
        }
    }

    func cancelPasswordRequest() {
        let remaining = passwordRequest?.remaining ?? []
        passwordRequest = nil
        guard !remaining.isEmpty else { return }
        Task { await load(remaining) }
    }

    /// Reads files one at a time, stopping at a locked PDF so the sheet can
    /// answer for it before the rest continue.
    private func load(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isReadingAttachment = true
        defer { isReadingAttachment = false }

        for (offset, url) in urls.enumerated() {
            guard attachments.count < Self.attachmentLimit else {
                attachmentError = "You can attach up to \(Self.attachmentLimit) files to one message."
                return
            }

            do {
                stage(try await AttachmentLoader.load(url: url))
            } catch let error as AttachmentError {
                if let name = error.lockedFileName {
                    passwordRequest = PasswordRequest(
                        url: url,
                        name: name,
                        remaining: Array(urls.dropFirst(offset + 1))
                    )
                    return
                }
                report(error)
            } catch {
                report(error)
            }
        }
    }

    private func stage(_ attachment: ChatAttachment) {
        guard !attachments.contains(where: { $0.name == attachment.name && $0.byteCount == attachment.byteCount })
        else { return }
        attachments.append(attachment)
    }

    private func report(_ error: Error) {
        attachmentError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// What to ask when a file is sent with no question of its own.
    private static func defaultAttachmentPrompt(for attachments: [ChatAttachment]) -> String {
        guard attachments.count == 1, let only = attachments.first else {
            return "Summarize these files and tell me what matters most in them."
        }
        switch only.kind {
        case .image:
            return "What is in this image?"
        case .pdf, .text:
            return "Summarize “\(only.name)” and tell me what matters most in it."
        }
    }

    // MARK: Private

    private func beginResponse(to prompt: String, in conversationID: UUID) {
        guard let index = index(of: conversationID) else { return }

        // The transcript so far travels with the prompt: the Gateway keeps no
        // history of its own, so context has to come from the app.
        let history = conversations[index].messages
        let answer = ChatMessage(role: .assistant, blocks: [], state: .thinking)
        conversations[index].messages.append(answer)

        responseTask?.cancel()
        responseTask = Task { [service] in
            do {
                for try await snapshot in service.respond(to: prompt, history: history) {
                    guard !Task.isCancelled else { return }
                    update(answer.id, in: conversationID) {
                        $0.blocks = snapshot
                        $0.state = .streaming
                    }
                }
                update(answer.id, in: conversationID) { $0.state = .complete }
            } catch {
                update(answer.id, in: conversationID) {
                    $0.state = .failed(AIErrorPresentation(error))
                }
            }
        }
    }

    private func cancelResponse() {
        responseTask?.cancel()
        responseTask = nil
    }

    private func update(_ messageID: UUID, in conversationID: UUID, _ body: (inout ChatMessage) -> Void) {
        guard let conversationIndex = index(of: conversationID),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID })
        else { return }
        body(&conversations[conversationIndex].messages[messageIndex])
    }

    private func openConversation(titledFrom prompt: String) -> UUID {
        let conversation = Conversation(title: ChatViewModel.title(from: prompt))
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        return conversation.id
    }

    private func index(of id: UUID?) -> Int? {
        guard let id else { return nil }
        return conversations.firstIndex { $0.id == id }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// A short, title-cased name taken from the opening prompt. Words are
    /// added whole until the title reaches the width the sidebar can show,
    /// so it never ends mid-phrase on a stray article.
    private static func title(from prompt: String) -> String {
        var words: [String] = []
        var length = 0

        for word in prompt.split(separator: " ") {
            guard length + word.count + 1 <= 28 else { break }
            words.append(word.prefix(1).uppercased() + word.dropFirst())
            length += word.count + 1
        }

        return words.isEmpty ? "New Chat" : words.joined(separator: " ")
    }

    private static var recentHistory: [Conversation] {
        [
            "Design App Onboarding",
            "Improve Landing Page UI",
            "Create App Store Screenshots",
            "Design Paywall Screen",
            "Improve Home Screen Layout"
        ]
        .enumerated()
        .map { offset, title in
            Conversation(title: title, updatedAt: Date().addingTimeInterval(-Double(offset) * 3600))
        }
    }
}
