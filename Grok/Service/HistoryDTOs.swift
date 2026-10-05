//
//  HistoryDTOs.swift
//  Grok
//
//  Created by Tricentric Labs on 05/10/2026.
//

import Foundation

/// The flattened forms the stores write.
///
/// Chat threads, PDF follow-ups and anything else that saves a message share
/// them, so an answer is written the same way wherever it is stored.

/// A `ResponseBlock` as it is written to disk. The enum itself stays free of
/// coding concerns; only this flattened form knows the storage format.
struct BlockDTO: Codable {
    let kind: String
    let text: String?
    let items: [ItemDTO]?

    init(_ block: ResponseBlock) {
        switch block {
        case .markdown(let text):
            kind = "markdown"
            self.text = text
            items = nil
        case .paragraph(let text):
            kind = "paragraph"
            self.text = text
            items = nil
        case .numberedList(let listItems):
            kind = "list"
            text = nil
            items = listItems.map(ItemDTO.init)
        }
    }

    var block: ResponseBlock? {
        switch kind {
        case "markdown":
            return text.map(ResponseBlock.markdown)
        // Threads saved before answers kept their Markdown.
        case "paragraph":
            return text.map(ResponseBlock.paragraph)
        case "list":
            return items.map { .numberedList($0.map(\.item)) }
        default:
            return nil
        }
    }
}

struct ItemDTO: Codable {
    let lead: String
    let body: String

    init(_ item: NumberedItem) {
        lead = item.lead
        body = item.body
    }

    var item: NumberedItem {
        NumberedItem(lead: lead, body: body)
    }
}

struct AttachmentDTO: Codable {
    let id: UUID
    let name: String
    let kind: String
    let byteCount: Int
    let text: String
    let pageCount: Int?
    let previewData: Data?

    init(_ attachment: ChatAttachment) {
        id = attachment.id
        name = attachment.name
        kind = attachment.kind.rawValue
        byteCount = attachment.byteCount
        text = attachment.text
        pageCount = attachment.pageCount
        previewData = attachment.previewData
    }

    var attachment: ChatAttachment {
        ChatAttachment(
            id: id,
            name: name,
            kind: AttachmentKind(rawValue: kind) ?? .text,
            byteCount: byteCount,
            text: text,
            pageCount: pageCount,
            previewData: previewData
        )
    }
}

/// A whole turn, for the places that keep messages as JSON rather than as
/// rows of their own — the questions asked about a PDF, for one.
struct MessageDTO: Codable {
    let id: UUID
    let role: String
    let blocks: [BlockDTO]
    let attachments: [AttachmentDTO]

    init(_ message: ChatMessage) {
        id = message.id
        role = message.role == .user ? "user" : "assistant"
        blocks = message.blocks.map(BlockDTO.init)
        attachments = message.attachments.map(AttachmentDTO.init)
    }

    var message: ChatMessage {
        ChatMessage(
            id: id,
            role: role == "user" ? .user : .assistant,
            blocks: blocks.compactMap(\.block),
            state: .complete,
            attachments: attachments.map(\.attachment)
        )
    }
}
