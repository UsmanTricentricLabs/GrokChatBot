//
//  GatewayIdentityAndConfigTests.swift
//  GrokTests
//
//  Created by Tricentric Labs on 01/10/2026.
//

import XCTest
@testable import Grok

final class GatewayIdentityTests: XCTestCase {

    func testIdentityIsAStableLowercaseUUID() {
        let first = GatewayUserIdentity.current
        let second = GatewayUserIdentity.current

        XCTAssertEqual(first, second, "The installation identifier must not change between calls.")
        XCTAssertEqual(first, first.lowercased(), "The identifier is sent lowercased.")
        XCTAssertNotNil(UUID(uuidString: first), "The identifier must be a UUID.")
    }

    func testIdentityCarriesNoPersonalInformation() {
        let identity = GatewayUserIdentity.current

        // A UUID has no account, device or contact information in it, and the
        // app has no sign-in that could supply any.
        XCTAssertFalse(identity.contains("@"))
        XCTAssertEqual(identity.count, 36)
        XCTAssertNotEqual(identity, Host.current().localizedName?.lowercased())
        XCTAssertNotEqual(identity, NSUserName().lowercased())
        XCTAssertNotEqual(identity, NSFullUserName().lowercased())
    }
}

final class GatewayConfigurationTests: XCTestCase {

    func testConfigurationMatchesTheRegisteredApp() {
        let configuration = GatewayConfiguration.shared

        XCTAssertEqual(configuration.appId, "grok_001")
        XCTAssertEqual(configuration.chatModel, "grok-4.3")
        XCTAssertEqual(configuration.imageModel, "gemini-2.5-flash-image")
        XCTAssertEqual(configuration.baseURL.scheme, "https")
        XCTAssertTrue(configuration.appKey.hasPrefix("aik_"))
    }

    /// The shipped app must contain no provider credential and no Gateway
    /// admin token. The Gateway holds every provider key.
    ///
    /// This scans the built product rather than the source tree, because the
    /// app is sandboxed and because the binary is what actually ships.
    func testShippedAppContainsNoProviderCredentials() throws {
        let forbidden = [
            "sk-ant-", "sk-proj-", "AIzaSy", "xai-",
            "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY", "XAI_API_KEY",
            "admin_token", "ADMIN_TOKEN"
        ]

        for (name, haystack) in try Self.shippedContents() {
            for marker in forbidden {
                XCTAssertFalse(
                    haystack.contains(marker),
                    "Found '\(marker)' in \(name). Provider credentials must never ship in the app."
                )
            }
        }
    }

    /// Nothing in the shipped app addresses a provider directly; every AI
    /// request goes through the Gateway host.
    func testShippedAppCallsNoProviderEndpointDirectly() throws {
        let providerHosts = [
            "api.openai.com", "api.anthropic.com", "generativelanguage.googleapis.com",
            "api.x.ai", "api.cohere.ai", "api.mistral.ai"
        ]

        for (name, haystack) in try Self.shippedContents() {
            for host in providerHosts {
                XCTAssertFalse(
                    haystack.contains(host),
                    "\(name) addresses \(host) directly; it must go through the Gateway."
                )
            }
        }
    }

    /// The app's own executable and configuration, as readable text. The
    /// injected test frameworks are deliberately excluded — they are not part
    /// of the shipped product.
    private static func shippedContents() throws -> [(String, String)] {
        var contents: [(String, String)] = []

        let executable = try XCTUnwrap(Bundle.main.executableURL)
        let binary = try Data(contentsOf: executable)
        contents.append((executable.lastPathComponent, String(decoding: binary, as: UTF8.self)))

        if let config = Bundle.main.url(forResource: "GatewayConfig", withExtension: "plist") {
            contents.append(("GatewayConfig.plist", try String(contentsOf: config, encoding: .utf8)))
        }
        if let info = Bundle.main.url(forResource: "Info", withExtension: "plist"),
           let text = try? String(contentsOf: info, encoding: .utf8) {
            contents.append(("Info.plist", text))
        }
        return contents
    }
}

final class AIErrorPresentationTests: XCTestCase {

    func testBudgetAndSubscriptionFailuresDoNotOfferRetry() {
        XCTAssertFalse(AIErrorPresentation(GatewayError.subscriptionRequired).isRetryable)
        XCTAssertFalse(AIErrorPresentation(GatewayError.budgetExceeded(resetsAt: nil)).isRetryable)
        XCTAssertFalse(AIErrorPresentation(GatewayError.appBudgetExceeded).isRetryable)
        XCTAssertFalse(AIErrorPresentation(GatewayError.configuration).isRetryable)
    }

    func testTransientFailuresOfferRetry() {
        XCTAssertTrue(AIErrorPresentation(GatewayError.temporary).isRetryable)
        XCTAssertTrue(AIErrorPresentation(GatewayError.network).isRetryable)
    }

    func testSubscriptionFailureIsFlaggedForTheSubscriptionFlow() {
        XCTAssertTrue(AIErrorPresentation(GatewayError.subscriptionRequired).requiresSubscription)
        XCTAssertFalse(AIErrorPresentation(GatewayError.temporary).requiresSubscription)
    }

    func testMessagesNeverLeakGatewayInternals() {
        let failures: [GatewayError] = [
            .subscriptionRequired, .budgetExceeded(resetsAt: nil), .rateLimited(retryAfter: 5),
            .appBudgetExceeded, .invalidRequest, .configuration, .payloadTooLarge,
            .providerRejected, .temporary, .network
        ]

        for failure in failures {
            let presentation = AIErrorPresentation(failure)
            for leak in ["request_id", "req_", "{", "}", "xai", "openai", "gemini", "provider"] {
                XCTAssertFalse(
                    presentation.title.lowercased().contains(leak),
                    "'\(leak)' leaked into a user-facing message."
                )
            }
            XCTAssertFalse(presentation.title.isEmpty)
        }
    }
}
