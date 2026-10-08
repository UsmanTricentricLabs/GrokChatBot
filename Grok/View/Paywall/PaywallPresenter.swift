//
//  PaywallPresenter.swift
//  Grok
//
//  Created by Tricentric Labs on 08/10/2026.
//

import SwiftUI
internal import Combine

/// Whether the upgrade dialog is on screen, and whether the launch offer has
/// already been made.
///
/// This is held above the shell rather than inside it because a language change
/// rebuilds the shell from scratch. Were the flags `@State` on `DockPage`, every
/// language change would reset them and offer the paywall all over again.
@MainActor
final class PaywallPresenter: ObservableObject {

    @Published var isPresented = false

    /// The launch offer is made once per run. A rebuilt shell must not count as
    /// a new launch.
    private var hasOfferedAtLaunch = false

    /// Offers the paywall a moment after launch, and only to a customer who is
    /// not already subscribed. `IAPManager` decides both.
    func offerAtLaunch(using iap: IAPManager) async {
        guard !hasOfferedAtLaunch else { return }
        hasOfferedAtLaunch = true

        guard await iap.shouldPresentPaywallAtLaunch() else { return }

        isPresented = true
    }
}
