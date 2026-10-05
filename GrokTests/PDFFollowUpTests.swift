//
//  PDFFollowUpTests.swift
//  GrokTests
//
//  Created by Tricentric Labs on 01/10/2026.
//

import PDFKit
import XCTest
@testable import Grok

/// Covers the follow-up question thread on a finished PDF summary, which
/// shares the Gateway chat path with the main conversation.
@MainActor
final class PDFFollowUpTests: XCTestCase {

    private var viewModel: PDFViewModel!
    private var documentURL: URL!
    /// A store of its own, so the documents saved on this machine are left
    /// alone.
    private var controller: PersistenceController!

    override func setUp() async throws {
        try await super.setUp()
        StubURLProtocol.reset()

        let client = GatewayClient(session: StubURLProtocol.session())
        var chat = GatewayChatService(client: client)
        chat.wordInterval = 0

        controller = PersistenceController(inMemory: true)
        viewModel = PDFViewModel(
            service: PDFSummaryService(client: client),
            chatService: chat,
            history: DocumentHistoryStore(controller: controller)
        )
        documentURL = try Self.makeDocument()

        // Reach a finished summary the way the app does: drop a file, then
        // summarize it. Follow-ups are only offered once a summary exists.
        StubURLProtocol.stub = .json(Self.summaryReply)
        viewModel.open(documentURL)
        try await waitUntil { self.viewModel.document != nil }

        viewModel.summarize()
        try await waitUntil { self.viewModel.summary != nil }
    }

    override func tearDown() async throws {
        StubURLProtocol.reset()
        if let documentURL { try? FileManager.default.removeItem(at: documentURL) }
        viewModel = nil
        documentURL = nil
        controller = nil
        try await super.tearDown()
    }

    func testTheSummaryIsReadyBeforeFollowUpsAreOffered() {
        XCTAssertNotNil(viewModel.summary)
        XCTAssertTrue(viewModel.followUps.isEmpty)
    }

    func testAskingAFollowUpAppendsTheQuestionAndTheAnswer() async throws {
        StubURLProtocol.stub = .json(TestFixtures.chatResponse)

        viewModel.followUpDraft = "What percent of signups come from free tiers?"
        viewModel.askFollowUp()
        try await waitForAnswer()

        XCTAssertEqual(viewModel.followUps.count, 2)
        XCTAssertEqual(viewModel.followUps[0].role, .user)
        XCTAssertEqual(viewModel.followUps[0].text, "What percent of signups come from free tiers?")
        XCTAssertEqual(viewModel.followUps[1].role, .assistant)
        XCTAssertEqual(viewModel.followUps[1].state, .complete)
        XCTAssertEqual(viewModel.followUps[1].text, "Hello there.")
        XCTAssertTrue(viewModel.followUpDraft.isEmpty, "The composer clears once sent.")
    }

    func testAnEmptyQuestionIsIgnored() {
        viewModel.followUpDraft = "   "
        viewModel.askFollowUp()

        XCTAssertTrue(viewModel.followUps.isEmpty)
    }

    func testGatewayFailureIsShownOnTheAnswer() async throws {
        StubURLProtocol.stub = .json(TestFixtures.error("subscription_required"), status: 402)

        viewModel.followUpDraft = "Why?"
        viewModel.askFollowUp()
        try await waitForAnswer()

        guard case .failed(let failure) = viewModel.followUps.last?.state else {
            return XCTFail("Expected the answer to carry a failure.")
        }
        XCTAssertTrue(failure.requiresSubscription)
        XCTAssertFalse(failure.isRetryable)
    }

    func testRemovingTheDocumentClearsTheFollowUpThread() async throws {
        StubURLProtocol.stub = .json(TestFixtures.chatResponse)

        viewModel.followUpDraft = "A question"
        viewModel.askFollowUp()
        try await waitForAnswer()
        XCTAssertFalse(viewModel.followUps.isEmpty)

        viewModel.removeDocument()

        XCTAssertTrue(viewModel.followUps.isEmpty, "A new document starts a new thread.")
        XCTAssertTrue(viewModel.followUpDraft.isEmpty)
    }

    func testPickingADocumentFromTheSidebarReopensItsSummary() async throws {
        StubURLProtocol.stub = .json(TestFixtures.chatResponse)
        viewModel.followUpDraft = "A question"
        viewModel.askFollowUp()
        try await waitForAnswer()

        let listed = try XCTUnwrap(viewModel.summarizedDocuments.first)
        let summary = try XCTUnwrap(viewModel.summary)

        viewModel.startNewSummary()
        XCTAssertNil(viewModel.summary, "The flow goes back to the drop zone.")

        // Nothing is stubbed, so reopening must come from what is already held
        // rather than from a second trip to the Gateway.
        StubURLProtocol.reset()
        viewModel.select(listed)

        XCTAssertEqual(viewModel.document?.url, listed.url)
        XCTAssertEqual(viewModel.summary, summary)
        XCTAssertEqual(viewModel.followUps.count, 2, "Its questions come back with it.")
    }

    /// Waits for the streamed answer to settle.
    private func waitForAnswer(timeout: TimeInterval = 5) async throws {
        try await waitUntil(timeout: timeout) {
            guard let last = self.viewModel.followUps.last else { return false }
            return last.role == .assistant && !last.isAwaitingResponse
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for the expected state.", file: file, line: line)
    }

    // MARK: Fixtures

    private static let summaryReply = """
        {
          "request_id": "req_test_pdf",
          "model": "grok-4.3",
          "message": { "role": "assistant", "content": "{\\"title\\": \\"Report\\", \\"overview\\": \\"An overview.\\", \\"key_points\\": [\\"A point.\\"], \\"sections\\": [{\\"title\\": \\"Intro\\", \\"page\\": 1}]}" }
        }
        """

    private static func makeDocument() throws -> URL {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 648))
        view.string = """
            Report

            Intro

            Free tiers now drive sixty four percent of new sign ups across the \
            category, which lowers paid conversion for every vendor measured here.
            Desktop usage rose faster than mobile for the first time this year, \
            driven by professionals who want assistance inside existing tools.
            Privacy and on device processing are the top reasons people give for \
            choosing a paid plan over a free alternative in this market.
            """

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokFollowUp-\(UUID().uuidString).pdf")
        try view.dataWithPDF(inside: view.bounds).write(to: url)
        return url
    }
}
