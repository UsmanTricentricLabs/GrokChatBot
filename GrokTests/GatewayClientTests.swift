//
//  GatewayClientTests.swift
//  GrokTests
//
//  Created by Tricentric Labs on 01/10/2026.
//

import XCTest
@testable import Grok

final class GatewayClientTests: XCTestCase {

    private var client: GatewayClient!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        client = GatewayClient(session: StubURLProtocol.session())
    }

    override func tearDown() {
        StubURLProtocol.reset()
        client = nil
        super.tearDown()
    }

    // MARK: Authentication

    func testEveryRequestCarriesGatewayHeaders() async throws {
        StubURLProtocol.stub = .json(TestFixtures.chatResponse)

        _ = try await client.chat(messages: [GatewayChatTurn(role: .user, content: "Hi")])

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-App-Id"), "grok_001")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-App-Key"),
            GatewayConfiguration.shared.appKey
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-User-Id"),
            GatewayUserIdentity.current
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testRequestsGoToTheGatewayAndNotToAProvider() async throws {
        StubURLProtocol.stub = .json(TestFixtures.chatResponse)

        _ = try await client.chat(messages: [GatewayChatTurn(role: .user, content: "Hi")])

        let url = try XCTUnwrap(StubURLProtocol.lastRequest?.url)
        XCTAssertEqual(url.host, "ai-gateway.tricentriclabs.workers.dev")
        XCTAssertEqual(url.path, "/v1/ai/chat")
        // No provider credential is ever attached.
        XCTAssertNil(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: Chat

    func testChatSendsConversationAndConfiguredModel() async throws {
        StubURLProtocol.stub = .json(TestFixtures.chatResponse)

        let response = try await client.chat(
            messages: [
                GatewayChatTurn(role: .user, content: "First"),
                GatewayChatTurn(role: .assistant, content: "Reply"),
                GatewayChatTurn(role: .user, content: "Second")
            ],
            system: "Be brief.",
            maxOutputTokens: 4096,
            temperature: 0.7
        )

        XCTAssertEqual(response.message.content, "Hello there.")

        let body = try XCTUnwrap(StubURLProtocol.lastJSON())
        XCTAssertEqual(body["model"] as? String, "grok-4.3")
        XCTAssertEqual(body["system"] as? String, "Be brief.")
        XCTAssertEqual(body["max_output_tokens"] as? Int, 4096)

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertEqual(messages[1]["role"] as? String, "assistant")
        XCTAssertEqual(messages[2]["content"] as? String, "Second")
    }

    // MARK: Image

    func testImageSendsOnlySupportedFields() async throws {
        StubURLProtocol.stub = .json(TestFixtures.imageResponse)

        let response = try await client.image(prompt: "A lighthouse")

        XCTAssertEqual(response.image.mimeType, "image/png")
        XCTAssertNotNil(Data(base64Encoded: response.image.data))

        let body = try XCTUnwrap(StubURLProtocol.lastJSON())
        XCTAssertEqual(body["prompt"] as? String, "A lighthouse")
        XCTAssertEqual(body["model"] as? String, "gemini-2.5-flash-image")

        // The endpoint rejects these, so they must never be sent.
        for field in ["size", "aspect_ratio", "n", "quality", "style", "response_format"] {
            XCTAssertNil(body[field], "Unsupported field '\(field)' was sent to the Gateway.")
        }
    }

    func testImageSendsReferenceWhenProvided() async throws {
        StubURLProtocol.stub = .json(TestFixtures.imageResponse)

        _ = try await client.image(
            prompt: "Make it warmer",
            reference: GatewayImagePayload(data: TestFixtures.pngBase64, mimeType: "image/png")
        )

        let body = try XCTUnwrap(StubURLProtocol.lastJSON())
        let image = try XCTUnwrap(body["image"] as? [String: Any])
        XCTAssertEqual(image["mime_type"] as? String, "image/png")
        XCTAssertFalse((image["data"] as? String ?? "").isEmpty)
    }

    // MARK: Errors

    func testSubscriptionRequiredIsSurfacedForPaywall() async {
        StubURLProtocol.stub = .json(TestFixtures.error("subscription_required"), status: 402)

        await assertChatFails(with: .subscriptionRequired)
    }

    func testBudgetExceededCarriesResetDateAndIsNotRetryable() async {
        StubURLProtocol.stub = .json(
            TestFixtures.error(
                "ai_budget_exceeded",
                details: #", "details": { "resets_at": "2026-10-02T00:00:00Z" }"#
            ),
            status: 429
        )

        do {
            _ = try await client.chat(messages: [GatewayChatTurn(role: .user, content: "Hi")])
            XCTFail("Expected the request to fail.")
        } catch let error as GatewayError {
            guard case .budgetExceeded(let resetsAt) = error else {
                return XCTFail("Expected a budget failure, got \(error).")
            }
            XCTAssertNotNil(resetsAt)
            XCTAssertFalse(error.isRetryable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAppBudgetExceededIsDistinctFromUserBudget() async {
        StubURLProtocol.stub = .json(TestFixtures.error("app_budget_exceeded"), status: 429)
        await assertChatFails(with: .appBudgetExceeded)
    }

    func testRateLimitUsesRetryAfterHeaderWhenBodyOmitsIt() async {
        StubURLProtocol.stub = .json(
            TestFixtures.error("rate_limited"),
            status: 429,
            headers: ["Retry-After": "12"]
        )

        await assertChatFails(with: .rateLimited(retryAfter: 12))
    }

    func testInvalidAppCredentialsAreTreatedAsConfiguration() async {
        StubURLProtocol.stub = .json(TestFixtures.error("invalid_app"), status: 401)
        await assertChatFails(with: .configuration)
    }

    func testPayloadTooLargeIsReported() async {
        StubURLProtocol.stub = .json(TestFixtures.error("payload_too_large"), status: 413)
        await assertChatFails(with: .payloadTooLarge)
    }

    func testProviderRejectionIsReported() async {
        StubURLProtocol.stub = .json(TestFixtures.error("provider_invalid_request"), status: 422)
        await assertChatFails(with: .providerRejected)
    }

    func testServerFailureIsRetryable() async {
        StubURLProtocol.stub = .json(TestFixtures.error("provider_unavailable"), status: 503)
        await assertChatFails(with: .temporary)
        XCTAssertTrue(GatewayError.temporary.isRetryable)
    }

    func testNetworkFailureIsReportedAsOffline() async {
        var stub = StubURLProtocol.Stub()
        stub.error = URLError(.notConnectedToInternet)
        StubURLProtocol.stub = stub

        await assertChatFails(with: .network)
    }

    // MARK: Cancellation

    func testCancellingARequestThrowsCancellation() async {
        var stub = StubURLProtocol.Stub.json(TestFixtures.chatResponse)
        stub.delay = 2
        StubURLProtocol.stub = stub

        let task = Task {
            try await client.chat(messages: [GatewayChatTurn(role: .user, content: "Hi")])
        }
        // Give the request time to start before pulling it.
        try? await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation.")
        } catch {
            XCTAssertTrue(error is CancellationError, "Expected CancellationError, got \(error).")
        }
    }

    // MARK: Helpers

    private func assertChatFails(
        with expected: GatewayError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await client.chat(messages: [GatewayChatTurn(role: .user, content: "Hi")])
            XCTFail("Expected the request to fail.", file: file, line: line)
        } catch let error as GatewayError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
