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
            detail = "Your message is saved."
            isRetryable = true
            requiresSubscription = false
        } else {
            title = Self.genericTitle
            detail = Self.genericDetail
            isRetryable = true
            requiresSubscription = false
        }
    }

    private static let genericTitle = "Something went wrong while generating a response."
    private static let genericDetail = "Check your connection and try again. Your message is saved."

    private static func detail(for error: GatewayError) -> String {
        switch error {
        case .network, .temporary, .providerRejected, .rateLimited:
            return genericDetail
        case .subscriptionRequired:
            return "Your message is saved."
        case .budgetExceeded, .appBudgetExceeded:
            return "Your message is saved."
        case .payloadTooLarge:
            return "Shorten it and send again."
        case .invalidRequest, .configuration:
            return "Please try again shortly. Your message is saved."
        }
    }
}
