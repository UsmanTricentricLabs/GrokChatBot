//
//  RatingManager.swift
//  Grok
//
//  Created by Tricentric Labs on 19/10/2026.
//

import AppKit
import StoreKit

/// Decides when the App Store's own rating prompt is asked for.
///
/// Three moments ask for it, and each is worth a review for a different
/// reason:
///
/// - the first answer that finishes on the second or any later launch, so the
///   app has been used once before being judged;
/// - quitting, which is the other point where the session has an opinion;
/// - the Settings menu's Rate Us row, which is the user asking for it.
///
/// Each automatic moment fires at most once per session, and the system
/// throttles the prompt on top of that — a few times a year, no more. Nothing
/// else stands in for it when it stays silent: the App Store is never opened
/// on the app's own initiative.
@MainActor
final class RatingManager {
    static let shared = RatingManager()

    private enum Key {
        static let launchCount = "rating.launchCount"
    }

    /// How many times the app has been launched, this launch included.
    private(set) var launchCount: Int

    private var hasPromptedAfterGeneration = false
    private var hasPromptedOnQuit = false

    private let defaults = UserDefaults.standard

    private init() {
        launchCount = defaults.integer(forKey: Key.launchCount)
    }

    // MARK: Triggers

    /// Counted once per launch, from the app delegate.
    func registerLaunch() {
        launchCount += 1
        defaults.set(launchCount, forKey: Key.launchCount)
    }

    /// A chat answer finished without an error.
    ///
    /// Held back on the very first launch: a first-run prompt asks for a
    /// verdict the user has not formed yet.
    func recordSuccessfulGeneration() {
        guard launchCount >= 2, !hasPromptedAfterGeneration else { return }
        hasPromptedAfterGeneration = true
        requestReview()
    }

    /// Asked for while the app is quitting.
    ///
    /// - Returns: `true` when a prompt was asked for, which tells the caller
    ///   termination has to wait for it to be answered.
    @discardableResult
    func requestReviewBeforeQuit() -> Bool {
        guard !hasPromptedOnQuit else { return false }
        hasPromptedOnQuit = true
        return requestReview()
    }

    /// The Settings menu's Rate Us row.
    ///
    /// Only the native prompt: the App Store listing is deliberately not
    /// opened behind it, because leaving the app is not what the row asked
    /// for. When the system has spent its allowance the prompt stays silent,
    /// and that is the whole of what happens.
    func requestReviewFromUser() {
        requestReview()
    }

    // MARK: Prompt

    /// Asks StoreKit for the prompt.
    ///
    /// - Returns: `false` when there is no window to put it over, which is the
    ///   one case where it is certain nothing will be shown.
    @discardableResult
    private func requestReview() -> Bool {
        let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible })
        guard let controller = window?.contentViewController else { return false }

        AppStore.requestReview(in: controller)
        return true
    }

    /// How many windows on screen look like the rating prompt: StoreKit puts
    /// it up either as its own window or as a sheet over the main one, and
    /// neither is a window the app made. Counting them is how an answered
    /// prompt is told apart from one that never appeared.
    private func promptWindows() -> Int {
        NSApp.windows.filter { window in
            guard window.isVisible else { return false }
            if window.isSheet { return true }
            let name = window.className
            return name.contains("SK") || name.contains("Review") || name.contains("Alert")
        }.count
    }

    /// True while the rating prompt is still on screen.
    var isPromptOnScreen: Bool { promptWindows() > 0 }
}
