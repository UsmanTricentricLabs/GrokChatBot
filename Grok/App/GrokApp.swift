//
//  GrokApp.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI
import AppKit
import CoreData

@main
struct GrokApp: App {
    let persistenceController = PersistenceController.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// The chosen language. Held at the root because changing it rebuilds the
    /// whole shell, not just the screen the picker was opened from.
    @StateObject private var localization = LocalizationManager.shared

    // The shell's models live here, above the language rebuild, so switching
    // language re-renders the UI without discarding what is in it.
    @StateObject private var screenSwitchVM = ScreenSwitchViewModel()
    @StateObject private var chatVM = ChatViewModel()
    @StateObject private var imageVM = ImageViewModel()
    @StateObject private var pdfVM = PDFViewModel()
    // Shared, because the view models ask the same object whether a feature
    // may run as the shell asks it whether to show the dialog.
    @StateObject private var paywall = PaywallPresenter.shared

    var body: some Scene {
        WindowGroup {
            DockPage(
                screenSwitchVM: screenSwitchVM,
                chatVM: chatVM,
                imageVM: imageVM,
                pdfVM: pdfVM,
                paywall: paywall
            )
                .frame(minWidth: 1280, minHeight: 736)
                .preferredColorScheme(.light)
                .localized(by: localization)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Grok is designed light-only, so the app pins itself to Aqua rather than
    /// following the system appearance. Setting it on `NSApplication` covers
    /// the AppKit surfaces SwiftUI does not reach — menus, popovers, the open
    /// and save panels and the window chrome.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
        RatingManager.shared.registerLaunch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Quitting is the last chance to ask for a rating, so the prompt goes up
    /// before the app goes away and termination waits for it.
    ///
    /// The wait is bounded twice over: nothing on screen after a moment means
    /// the system swallowed the prompt, and even an unanswered one only holds
    /// the quit for `promptPatience` before the app closes anyway.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard RatingManager.shared.requestReviewBeforeQuit() else { return .terminateNow }
        waitForRatingPrompt(deadline: Date().addingTimeInterval(Self.promptPatience))
        return .terminateLater
    }

    /// How long a quit waits for the rating prompt to be answered.
    private static let promptPatience: TimeInterval = 30

    private func waitForRatingPrompt(deadline: Date) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let appeared = RatingManager.shared.isPromptOnScreen
            if appeared, Date() < deadline {
                self.waitForRatingPrompt(deadline: deadline)
            } else {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
    }
}
