//
//  ChatHistoryStoreTests.swift
//  GrokTests
//
//  Created by Tricentric Labs on 02/10/2026.
//

import XCTest
@testable import Grok

@MainActor
final class ChatHistoryStoreTests: XCTestCase {

    /// A store of its own per test, so one test's history never reaches
    /// another's.
    private func makeStore() -> ChatHistoryStore {
        ChatHistoryStore(controller: PersistenceController(inMemory: true))
    }

    func testSavedConversationsComeBackWithTheirTurns() {
        let store = makeStore()
        XCTAssertTrue(store.isEmpty)

        let conversation = Conversation(
            title: "Sleep & Memory Research",
            messages: [
                ChatMessage(role: .user, text: "How does sleep affect memory?"),
                ChatMessage(role: .assistant, text: "It consolidates it overnight.")
            ],
            isPinned: true
        )
        store.save([conversation])

        let loaded = store.load()
        XCTAssertFalse(store.isEmpty)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, conversation.id)
        XCTAssertEqual(loaded.first?.title, "Sleep & Memory Research")
        XCTAssertEqual(loaded.first?.isPinned, true)
        XCTAssertEqual(loaded.first?.messages.map(\.text), [
            "How does sleep affect memory?",
            "It consolidates it overnight."
        ])
        XCTAssertEqual(loaded.first?.messages.map(\.role), [.user, .assistant])
    }

    func testListBlocksAndAttachmentsSurviveTheRoundTrip() {
        let store = makeStore()
        let attachment = ChatAttachment(
            name: "notes.pdf",
            kind: .pdf,
            byteCount: 2048,
            text: "Page one.",
            pageCount: 3
        )
        let answer = ChatMessage(
            role: .assistant,
            blocks: [
                .paragraph("Here are the steps:"),
                .numberedList([NumberedItem(lead: "Sleep first.", body: "Then review.")])
            ]
        )
        store.save([
            Conversation(
                title: "Notes",
                messages: [
                    ChatMessage(role: .user, text: "Summarise this", attachments: [attachment]),
                    answer
                ]
            )
        ])

        let loaded = store.load().first
        XCTAssertEqual(loaded?.messages.first?.attachments.first?.name, "notes.pdf")
        XCTAssertEqual(loaded?.messages.first?.attachments.first?.pageCount, 3)
        // Block identity is regenerated on load, so the text is what is
        // compared.
        XCTAssertEqual(loaded?.messages.last?.text, answer.text)
    }

    /// Saving is a replace, so a deleted conversation does not come back.
    func testSavingReplacesWhatWasStored() {
        let store = makeStore()
        store.save([Conversation(title: "First"), Conversation(title: "Second")])
        store.save([Conversation(title: "Second")])

        XCTAssertEqual(store.load().map(\.title), ["Second"])
    }

    /// An answer still streaming would come back as a stuck spinner, so it is
    /// not written until it finishes.
    func testUnfinishedAnswersAreNotStored() {
        let store = makeStore()
        store.save([
            Conversation(
                title: "In flight",
                messages: [
                    ChatMessage(role: .user, text: "Hello"),
                    ChatMessage(role: .assistant, text: "", state: .thinking)
                ]
            )
        ])

        XCTAssertEqual(store.load().first?.messages.count, 1)
    }
}
