//
//  PDFSummaryGatewayTests.swift
//  GrokTests
//
//  Created by Tricentric Labs on 01/10/2026.
//

import PDFKit
import XCTest
@testable import Grok

final class PDFSummaryGatewayTests: XCTestCase {

    private var service: PDFSummaryService!
    private var document: PDFDocumentInfo!

    override func setUpWithError() throws {
        try super.setUpWithError()
        StubURLProtocol.reset()
        service = PDFSummaryService(client: GatewayClient(session: StubURLProtocol.session()))
        document = try Self.makeDocument()
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        if let document { try? FileManager.default.removeItem(at: document.url) }
        service = nil
        document = nil
        try super.tearDownWithError()
    }

    func testSummaryUsesTheGatewayReply() async throws {
        StubURLProtocol.stub = .json(Self.gatewayReply(content: Self.modelJSON))

        let summary = try await service.summarize(document, length: .standard) { _ in }

        XCTAssertEqual(summary.title, "Q3 2026 Market Report")
        XCTAssertTrue(summary.overview.hasPrefix("The Q3 2026 Market Report examines"))
        XCTAssertEqual(summary.keyPoints.count, 4)
        XCTAssertEqual(summary.sections.first?.title, "Market Size and Growth")
        XCTAssertEqual(summary.sections.first?.page, 1)
    }

    func testOnlyDocumentTextIsSentAndTheChatModelIsUsed() async throws {
        StubURLProtocol.stub = .json(Self.gatewayReply(content: Self.modelJSON))

        _ = try await service.summarize(document, length: .brief) { _ in }

        let body = try XCTUnwrap(StubURLProtocol.lastJSON())
        XCTAssertEqual(body["model"] as? String, "grok-4.3")

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(content.contains("Fresnel"), "The document's own text should be sent.")
        XCTAssertTrue(content.contains("[page 1]"), "Page markers let the model cite pages.")
    }

    func testProgressIsReportedForEveryPage() async throws {
        StubURLProtocol.stub = .json(Self.gatewayReply(content: Self.modelJSON))

        var pages: [Int] = []
        _ = try await service.summarize(document, length: .standard) { pages.append($0) }

        XCTAssertEqual(pages, Array(1...document.pageCount))
    }

    /// A reply the app cannot parse must still fill the screen, using the
    /// local extractive summary rather than failing.
    func testUnreadableReplyFallsBackToTheLocalSummary() async throws {
        StubURLProtocol.stub = .json(Self.gatewayReply(content: "I could not do that."))

        let summary = try await service.summarize(document, length: .standard) { _ in }

        XCTAssertFalse(summary.keyPoints.isEmpty)
        XCTAssertFalse(summary.overview.isEmpty)
    }

    /// A fenced reply is still usable — the parser reads the object out of it.
    func testFencedJSONIsAccepted() async throws {
        let fenced = "```json\\n\(Self.modelJSON)\\n```"
        StubURLProtocol.stub = .json(Self.gatewayReply(content: fenced))

        let summary = try await service.summarize(document, length: .standard) { _ in }

        XCTAssertEqual(summary.title, "Q3 2026 Market Report")
    }

    /// Budget and subscription failures must reach the user, not be hidden
    /// behind a local summary.
    func testBudgetFailureIsSurfacedRatherThanMasked() async {
        StubURLProtocol.stub = .json(TestFixtures.error("ai_budget_exceeded"), status: 429)

        do {
            _ = try await service.summarize(document, length: .standard) { _ in }
            XCTFail("Expected the budget failure to surface.")
        } catch let error as GatewayError {
            guard case .budgetExceeded = error else {
                return XCTFail("Expected a budget failure, got \(error).")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// A transient failure should not block the user, so the local summary
    /// stands in.
    func testTransientFailureFallsBackToTheLocalSummary() async throws {
        StubURLProtocol.stub = .json(TestFixtures.error("provider_timeout"), status: 504)

        let summary = try await service.summarize(document, length: .standard) { _ in }

        XCTAssertFalse(summary.keyPoints.isEmpty)
    }

    // MARK: Fixtures

    private static let modelJSON = """
        {"title": "Q3 2026 Market Report", \
        "overview": "The Q3 2026 Market Report examines growth in consumer AI tools. \
        Desktop usage rose faster than mobile for the first time this year. \
        Free tiers now dominate new sign-ups. Privacy drives paid conversion.", \
        "key_points": ["Demand grew steadily through Q3.", "Desktop grew thirty one percent.", \
        "Free tiers drive sixty four percent of sign ups.", "Privacy is the top paid driver."], \
        "sections": [{"title": "Market Size and Growth", "page": 1}, \
        {"title": "Pricing and Conversion", "page": 1}]}
        """

    private static func gatewayReply(content: String) -> String {
        let escaped = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return """
            {
              "request_id": "req_test_pdf",
              "model": "grok-4.3",
              "message": { "role": "assistant", "content": "\(escaped)" }
            }
            """
    }

    /// A small real PDF, so PDFKit extraction runs exactly as it does in the app.
    private static func makeDocument() throws -> PDFDocumentInfo {
        let text = """
            Q3 2026 Market Report

            Market Size and Growth

            Demand for consumer AI tools grew steadily through Q3, led by productivity \
            and creative applications across desktop and mobile. A Fresnel lens appears \
            here only so the test can prove the document's own text is what gets sent.

            Pricing and Conversion

            Free tiers now drive sixty four percent of new sign ups across the category, \
            which lowers paid conversion for every vendor measured in this report.
            """

        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 648))
        view.string = text
        let data = view.dataWithPDF(inside: view.bounds)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokTest-\(UUID().uuidString).pdf")
        try data.write(to: url)

        return try PDFSummaryService.inspect(url: url)
    }
}
