//
//  ChatModels.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import Foundation

/// One rendered piece of an assistant answer. Answers are modelled as blocks
/// rather than one string so numbered lists keep their medium-weight lead,
/// exactly as the design specifies.
nonisolated enum ResponseBlock: Identifiable, Equatable {
    case paragraph(String)
    case numberedList([NumberedItem])

    var id: String {
        switch self {
        case .paragraph(let text): return "p-\(text.hashValue)"
        case .numberedList(let items): return "l-\(items.map(\.id.uuidString).joined())"
        }
    }

    /// Plain-text rendering, used when the answer is copied to the pasteboard.
    var plainText: String {
        switch self {
        case .paragraph(let text):
            return text
        case .numberedList(let items):
            return items.enumerated()
                .map { "\($0.offset + 1). \($0.element.lead) \($0.element.body)" }
                .joined(separator: "\n")
        }
    }
}

nonisolated struct NumberedItem: Identifiable, Equatable {
    let id = UUID()
    /// The medium-weight opening phrase.
    let lead: String
    let body: String
}

nonisolated enum MessageRole {
    case user
    case assistant
}

/// How far along an assistant message is. The chat screen renders a different
/// answer slot for each: shimmering label, streaming text, finished actions
/// or the quiet error row.
nonisolated enum MessageState: Equatable {
    case thinking
    case streaming
    case complete
    case failed(AIErrorPresentation)
}

nonisolated struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    var blocks: [ResponseBlock]
    var state: MessageState
    /// Files sent with this turn. The bubble shows them as chips; the model
    /// receives their extracted text through `modelText`.
    var attachments: [ChatAttachment]

    init(
        id: UUID = UUID(),
        role: MessageRole,
        text: String,
        state: MessageState = .complete,
        attachments: [ChatAttachment] = []
    ) {
        self.init(id: id, role: role, blocks: [.paragraph(text)], state: state, attachments: attachments)
    }

    init(
        id: UUID = UUID(),
        role: MessageRole,
        blocks: [ResponseBlock],
        state: MessageState = .complete,
        attachments: [ChatAttachment] = []
    ) {
        self.id = id
        self.role = role
        self.blocks = blocks
        self.state = state
        self.attachments = attachments
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
            && lhs.blocks == rhs.blocks
            && lhs.state == rhs.state
            && lhs.attachments == rhs.attachments
    }

    var text: String {
        blocks.map(\.plainText).joined(separator: "\n\n")
    }

    /// The turn as the model sees it: each attachment's text, then the
    /// question. Without attachments this is simply what was typed.
    var modelText: String {
        guard !attachments.isEmpty else { return text }

        var parts = attachments.map { attachment -> String in
            let header = "Attached \(attachment.kind.contextLabel) “\(attachment.name)”:"
            return attachment.hasText
                ? "\(header)\n\(attachment.text)"
                : "\(header)\n(No readable text could be extracted from this file.)"
        }
        if !text.isEmpty { parts.append(text) }
        return parts.joined(separator: "\n\n")
    }

    var isAwaitingResponse: Bool {
        state == .thinking || state == .streaming
    }
}

nonisolated struct Conversation: Identifiable, Equatable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var isPinned: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        messages: [ChatMessage] = [],
        isPinned: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.isPinned = isPinned
        self.updatedAt = updatedAt
    }
}
