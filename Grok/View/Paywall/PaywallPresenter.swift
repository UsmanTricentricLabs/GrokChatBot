//
//  PaywallPresenter.swift
//  Grok
//
//  Created by Tricentric Labs on 08/10/2026.
//

import SwiftUI
internal import Combine

/// Whether the upgrade dialog is on screen, and whether the app's one free
/// run has been spent.
///
/// The app is given away once. A customer who has not subscribed may run any
/// one AI feature — a chat answer, an image, a PDF summary, a follow-up —
/// through to the end, undisturbed: the result is theirs to read. It is the
/// *next* attempt that is stopped, and that is when the paywall goes up, for
/// every one of those features, until a subscription unlocks them all.
///
/// The paywall is still offered a moment after launch, as before; closing it
/// is what leaves the free run available.
///
/// This is held above the shell rather than inside it because a language change
/// rebuilds the shell from scratch. Were the flags `@State` on `DockPage`, every
/// language change would reset them and offer the paywall all over again. The
/// view models reach the same instance through `shared`, so the gate they ask
/// and the dialog the shell shows are one object.
@MainActor
final class PaywallPresenter: ObservableObject {

    static let shared = PaywallPresenter()

    /// The gate and the launch offer. Set to `false` to give the app away
    /// whole while it is being tested: the dialog, the plans and the purchase
    /// flow all stay where they are, and only the asking stops.
    static let isEnforced = true

    @Published var isPresented = false

    /// Whether the free run has been used up. Persisted, so it is spent for
    /// good rather than once per launch.
    @Published private(set) var hasSpentFreeRun: Bool

    /// The launch offer is made once per run. A rebuilt shell must not count as
    /// a new launch.
    private var hasOfferedAtLaunch = false

    private let defaults = UserDefaults.standard
    private static let freeRunKey = "paywall.hasSpentFreeRun"

    private init() {
        hasSpentFreeRun = defaults.bool(forKey: Self.freeRunKey)
    }

    // MARK: Gate

    /// Asks permission to run an AI feature.
    ///
    /// - Returns: `true` when the work may go ahead — always for a subscriber,
    ///   and once for everyone else. A refusal puts the paywall up, so the
    ///   caller only has to stop.
    func claimRun(using iap: IAPManager = .shared) -> Bool {
        guard Self.isEnforced else { return true }
        if iap.isPremiumUnlocked { return true }

        guard !hasSpentFreeRun else {
            isPresented = true
            return false
        }

        hasSpentFreeRun = true
        defaults.set(true, forKey: Self.freeRunKey)
        return true
    }

    // MARK: Launch

    /// Offers the paywall a moment after launch, and only to a customer who is
    /// not already subscribed. `IAPManager` decides both.
    ///
    /// The free run is not spent by seeing this — the dialog can be closed and
    /// the one free feature used, which is what the offer is advertising.
    func offerAtLaunch(using iap: IAPManager) async {
        guard Self.isEnforced else { return }
        guard !hasOfferedAtLaunch else { return }
        hasOfferedAtLaunch = true

        guard await iap.shouldPresentPaywallAtLaunch() else { return }

        isPresented = true
    }
}
