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
    var body: some Scene {
        WindowGroup {
            DockPage()
                .frame(minWidth: 1280, minHeight: 736)
                .preferredColorScheme(.light)
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
