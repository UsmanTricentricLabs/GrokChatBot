//
//  GatewayError.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import Foundation
import os

/// A failure returned by the Gateway, or a transport failure reaching it.
///
/// Every case carries a user-facing sentence suitable for the app's existing
/// error UI. Gateway internals — raw JSON, provider names, the request body —
/// never reach the user; they go to the log, keyed by `request_id`.
nonisolated enum GatewayError: LocalizedError, Equatable {

    /// 402 — the user needs a subscription to continue.
    case subscriptionRequired
    /// 429 — the user's AI budget for the current period is spent.
    case budgetExceeded(resetsAt: Date?)
    /// 429 — too many requests; honour `retry_after_seconds`.
    case rateLimited(retryAfter: TimeInterval?)
    /// 429 — the whole app's budget is spent, not just this user's.
    case appBudgetExceeded
    /// 400 — a request the Gateway rejected. A developer problem, so the user
    /// sees a generic message.
    case invalidRequest
    /// 401 / 403 — the app's credentials are wrong or the app is disabled.
    case configuration
    /// 413 — the prompt or image exceeded the accepted size.
    case payloadTooLarge
    /// 422 — the provider rejected the request.
    case providerRejected
    /// 5xx — a temporary provider or Gateway failure; retrying is reasonable.
    case temporary
    /// The request never reached the Gateway.
    case network

    // MARK: Presentation

    var errorDescription: String? {
        switch self {
        case .subscriptionRequired:
            return "error.subscriptionRequired".localized
        case .budgetExceeded(let resetsAt):
            guard let resetsAt else {
                return "error.budget.now".localized
            }
            return "error.budget.resets".localized(Self.relative(resetsAt))
        case .rateLimited(let retryAfter):
            guard let retryAfter, retryAfter > 0 else {
                return "error.rateLimited.soon".localized
            }
            return "error.rateLimited.seconds".localized(Int(retryAfter.rounded()))
        case .appBudgetExceeded:
            return "error.temporary.later".localized
        case .invalidRequest, .configuration:
            return "error.generic.title".localized
        case .payloadTooLarge:
            return "error.payloadTooLarge".localized
        case .providerRejected:
            return "error.invalidRequest".localized
        case .temporary:
            return "error.temporary".localized
        case .network:
            return "error.network".localized
        }
    }

    /// Whether offering the user a retry makes sense. Budget, subscription and
    /// credential failures will not resolve by trying again.
    var isRetryable: Bool {
        switch self {
        case .temporary, .network, .rateLimited, .providerRejected:
            return true
        case .subscriptionRequired, .budgetExceeded, .appBudgetExceeded,
             .invalidRequest, .configuration, .payloadTooLarge:
            return false
        }
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// The Gateway's error envelope.
nonisolated struct GatewayErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let code: String
        let message: String
        let requestId: String?
        let retryAfterSeconds: Double?
        let resetsAt: Date?

        private enum CodingKeys: String, CodingKey {
            case code, message
            case requestId = "request_id"
            case retryAfterSeconds = "retry_after_seconds"
            case details
        }

        private enum DetailKeys: String, CodingKey {
            case resetsAt = "resets_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = try container.decode(String.self, forKey: .code)
            message = try container.decode(String.self, forKey: .message)
            requestId = try container.decodeIfPresent(String.self, forKey: .requestId)

            // The Gateway sends this as a number in some responses and a
            // string in others, so accept both rather than failing the decode.
            if let seconds = try? container.decodeIfPresent(Double.self, forKey: .retryAfterSeconds) {
                retryAfterSeconds = seconds
            } else if let text = try? container.decodeIfPresent(String.self, forKey: .retryAfterSeconds) {
                retryAfterSeconds = Double(text)
            } else {
                retryAfterSeconds = nil
            }

            let details = try? container.nestedContainer(keyedBy: DetailKeys.self, forKey: .details)
            if let text = try? details?.decodeIfPresent(String.self, forKey: .resetsAt) {
                resetsAt = ISO8601DateFormatter().date(from: text)
            } else {
                resetsAt = nil
            }
        }
    }

    let error: Payload
}

nonisolated extension GatewayError {
    static let log = Logger(subsystem: "com.grok.ai.app", category: "gateway")

    /// Maps a Gateway failure response onto a typed error, logging the detail a
    /// developer needs — including the request id — without surfacing it.
    static func make(status: Int, envelope: GatewayErrorEnvelope?, retryAfterHeader: TimeInterval?) -> GatewayError {
        let code = envelope?.error.code
        let requestId = envelope?.error.requestId ?? "none"
        log.error(
            """
            Gateway request failed. status=\(status, privacy: .public) \
            code=\(code ?? "unknown", privacy: .public) \
            request_id=\(requestId, privacy: .public) \
            message=\(envelope?.error.message ?? "none", privacy: .public)
            """
        )

        let retryAfter = envelope?.error.retryAfterSeconds ?? retryAfterHeader

        switch (status, code) {
        case (402, _):
            return .subscriptionRequired
        case (429, "ai_budget_exceeded"):
            return .budgetExceeded(resetsAt: envelope?.error.resetsAt)
        case (429, "app_budget_exceeded"):
            return .appBudgetExceeded
        case (429, _):
            return .rateLimited(retryAfter: retryAfter)
        case (413, _):
            return .payloadTooLarge
        case (422, _):
            return .providerRejected
        case (401, _), (403, _):
            return .configuration
        case (400, _):
            return .invalidRequest
        case (500..<600, _):
            return .temporary
        default:
            return .temporary
        }
    }
}
