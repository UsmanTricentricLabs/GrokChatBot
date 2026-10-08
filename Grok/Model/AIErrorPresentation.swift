//
//  AIErrorPresentation.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import Foundation

/// A failure rendered for the person using the app.
///
/// Every AI failure — Gateway, provider or network — is funnelled through here
/// so the error row shows a plain sentence and offers Try Again only when
/// trying again could actually help. Nothing technical reaches the screen; the
/// diagnostic detail is already in the log, keyed by the Gateway request id.
nonisolated struct AIErrorPresentation: Equatable {
    let title: String
    let detail: String
    let isRetryable: Bool
    /// Set when the failure is one the app's subscription flow should answer.
    let requiresSubscription: Bool

    init(_ error: Error) {
        if let gateway = error as? GatewayError {
            title = gateway.errorDescription ?? Self.genericTitle
            detail = Self.detail(for: gateway)
            isRetryable = gateway.isRetryable
            requiresSubscription = gateway == .subscriptionRequired
        } else if (error as? URLError) != nil {
            let offline = GatewayError.network
            title = offline.errorDescription ?? Self.genericTitle
            detail = "error.messageSaved".localized
            isRetryable = true
            requiresSubscription = false
        } else {
            title = Self.genericTitle
            detail = Self.genericDetail
            isRetryable = true
            requiresSubscription = false
        }
    }

    private static var genericTitle: String { "error.generic.title".localized }
    private static var genericDetail: String { "error.generic.detail".localized }

    private static func detail(for error: GatewayError) -> String {
        switch error {
        case .network, .temporary, .providerRejected, .rateLimited:
            return genericDetail
        case .subscriptionRequired:
            return "error.messageSaved".localized
        case .budgetExceeded, .appBudgetExceeded:
            return "error.messageSaved".localized
        case .payloadTooLarge:
            return "error.shortenAndResend".localized
        case .invalidRequest, .configuration:
            return "error.tryShortly".localized
        }
    }
}
