//
//  ChatHistoryStore.swift
//  Grok
//
//  Created by Tricentric Labs on 02/10/2026.
//

import CoreData
import Foundation

/// Where the sidebar's chat history lives between launches.
///
/// Conversations and their turns are Core Data rows; the parts of a turn that
/// have shape of their own — the answer blocks and the attachments — travel as
/// JSON inside the row, since nothing ever queries into them.
/// A value, not an object: it owns no state beyond the context it writes
/// through, and nothing has to watch it.
@MainActor
struct ChatHistoryStore {

    static let shared = ChatHistoryStore()

    private let context: NSManagedObjectContext

    init(controller: PersistenceController = .shared) {
        self.context = controller.container.viewContext
    }

    // MARK: Reading

    /// Every stored conversation, newest first. The sidebar sorts them again
    /// for pinning, so the order here only has to be stable.
    func load() -> [Conversation] {
        let request = NSFetchRequest<CDConversation>(entityName: "CDConversation")
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        do {
            return try context.fetch(request).map(Self.conversation(from:))
        } catch {
            NSLog("Chat history could not be read: \(error.localizedDescription)")
            return []
        }
    }

    /// True before anything has ever been written, which is how the app knows
    /// to lay down its sample history once.
    var isEmpty: Bool {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "CDConversation")
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) == 0
    }

    // MARK: Writing

    /// Replaces the stored history with what the view model is holding.
    ///
    /// The list is small — a few dozen rows at most — so rewriting it whole is
    /// both simpler and less error-prone than diffing, and it keeps deletes,
    /// renames and new turns on one path.
    func save(_ conversations: [Conversation]) {
        do {
            let request = NSFetchRequest<CDConversation>(entityName: "CDConversation")
            for existing in try context.fetch(request) {
                context.delete(existing)
            }

            for conversation in conversations {
                let row = CDConversation(context: context)
                row.id = conversation.id
                row.title = conversation.title
                row.isPinned = conversation.isPinned
                row.updatedAt = conversation.updatedAt

                for (index, message) in conversation.messages.enumerated() where Self.isStorable(message) {
                    let messageRow = CDMessage(context: context)
                    messageRow.id = message.id
                    messageRow.roleRaw = message.role == .user ? "user" : "assistant"
                    messageRow.order = Int32(index)
                    messageRow.blocksData = try? Self.encoder.encode(message.blocks.map(BlockDTO.init))
                    messageRow.attachmentsData = message.attachments.isEmpty
                        ? nil
                        : try? Self.encoder.encode(message.attachments.map(AttachmentDTO.init))
                    messageRow.conversation = row
                }
            }

            guard context.hasChanges else { return }
            try context.save()
        } catch {
            NSLog("Chat history could not be saved: \(error.localizedDescription)")
            context.rollback()
        }
    }

    /// An answer still being produced, or one that failed, has nothing worth
    /// restoring: it would come back as a spinner or an empty error row.
    private static func isStorable(_ message: ChatMessage) -> Bool {
        message.role == .user || message.state == .complete
    }

    // MARK: Mapping

    private static func conversation(from row: CDConversation) -> Conversation {
        let messages = (row.messages as? Set<CDMessage> ?? [])
            .sorted { $0.order < $1.order }
            .map(message(from:))

        return Conversation(
            id: row.id ?? UUID(),
            title: row.title ?? "",
            messages: messages,
            isPinned: row.isPinned,
            updatedAt: row.updatedAt ?? Date()
        )
    }

    private static func message(from row: CDMessage) -> ChatMessage {
        let blocks = (row.blocksData.flatMap { try? decoder.decode([BlockDTO].self, from: $0) } ?? [])
            .compactMap(\.block)
        let attachments = (row.attachmentsData.flatMap { try? decoder.decode([AttachmentDTO].self, from: $0) } ?? [])
            .map(\.attachment)

        return ChatMessage(
            id: row.id ?? UUID(),
            role: row.roleRaw == "user" ? .user : .assistant,
            blocks: blocks,
            state: .complete,
            attachments: attachments
        )
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}
