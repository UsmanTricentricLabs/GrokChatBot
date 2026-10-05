//
//  ChatGatewayIntegrationTests.swift
//  GrokTests
//
//  Created by Tricentric Labs on 01/10/2026.
//

import XCTest
@testable import Grok

final class GatewayChatServiceTests: XCTestCase {

    private func service() -> GatewayChatService {
        var service = GatewayChatService(client: GatewayClient(session: StubURLProtocol.session()))
        // Reveal instantly so tests do not wait on the streaming animation.
        service.wordInterval = 0
        return service
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testTranscriptIsSentWithThePrompt() async throws {
        StubURLProtocol.stub = .json(TestFixtures.chatResponse)

        let history = [
            ChatMessage(role: .user, text: "What is a Fresnel lens?"),
            ChatMessage(role: .assistant, text: "A flat lens made of concentric rings.")
        ]

        for try await _ in service().respond(to: "Why are they used in lighthouses?", history: history) {}

        let body = try XCTUnwrap(StubURLProtocol.lastJSON())
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])

        XCTAssertEqual(messages.count, 3, "History plus the new prompt should be sent.")
        XCTAssertEqual(messages[0]["content"] as? String, "What is a Fresnel lens?")
        XCTAssertEqual(messages[1]["role"] as? String, "assistant")
        XCTAssertEqual(messages[2]["content"] as? String, "Why are they used in lighthouses?")
    }

    func testUnansweredMessagesAreNotSentAsHistory() async throws {
        StubURLProtocol.stub = .json(TestFixtures.chatResponse)

        let history = [
            ChatMessage(role: .user, text: "Earlier question"),
            ChatMessage(role: .assistant, blocks: [], state: .thinking)
        ]

        for try await _ in service().respond(to: "New question", history: history) {}

        let messages = try XCTUnwrap(StubURLProtocol.lastJSON()?["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2, "A pending answer must not be sent as context.")
    }

    func testStreamEndsWithTheCompleteAnswer() async throws {
        StubURLProtocol.stub = .json(TestFixtures.chatResponse)

        var snapshots: [[ResponseBlock]] = []
        for try await snapshot in service().respond(to: "Hi") {
            snapshots.append(snapshot)
        }

        XCTAssertFalse(snapshots.isEmpty, "The view needs progressive snapshots to animate.")
        XCTAssertEqual(snapshots.last?.first, .markdown("Hello there."))
    }

    func testGatewayFailurePropagatesToTheCaller() async {
        StubURLProtocol.stub = .json(TestFixtures.error("subscription_required"), status: 402)

        do {
            for try await _ in service().respond(to: "Hi") {}
            XCTFail("Expected the stream to fail.")
        } catch let error as GatewayError {
            XCTAssertEqual(error, .subscriptionRequired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// The reply reaches the view as Markdown, so AIFormattingKit — not the app —
    /// decides how headings, lists, tables and code are drawn.
    func testAnswersArriveAsMarkdownWithTheirMarkersIntact() async throws {
        let markdown = "## Steps\n\n1. **Pick a focus.** One tap.\n\n```swift\nlet x = 1\n```"
        StubURLProtocol.stub = .json(TestFixtures.chatResponse(content: markdown))

        var snapshots: [[ResponseBlock]] = []
        for try await snapshot in service().respond(to: "Hi") {
            snapshots.append(snapshot)
        }

        XCTAssertEqual(snapshots.last, [.markdown(markdown)])
        XCTAssertTrue(
            snapshots.allSatisfy { snapshot in
                guard case .markdown = snapshot.first else { return false }
                return snapshot.count == 1
            },
            "Every snapshot should be one growing Markdown block."
        )
    }
}
