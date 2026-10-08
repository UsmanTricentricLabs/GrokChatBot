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
    @StateObject private var paywall = PaywallPresenter()

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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
