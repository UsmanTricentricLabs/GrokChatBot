//
//  SideBarRowMenu.swift
//  Grok
//
//  Created by Tricentric Labs on 08/10/2026.
//

import AppKit
import SwiftUI

/// One entry in a sidebar row's menu.
struct SideBarMenuEntry {
    let title: String
    /// Destructive entries are separated from the rest, the way the chat row
    /// sets Delete apart.
    var isDestructive: Bool = false
    let run: () -> Void
}

/// The hover-revealed "⋯" button on a sidebar row, and the menu behind it.
///
/// This is an AppKit menu rather than a SwiftUI `Menu` for the same reason the
/// conversation row uses one: the pop-up button SwiftUI draws re-renders the
/// label with its own styling, which drops the rotation and the white tint the
/// design asks for.
struct SideBarRowMenu: View {
    let entries: [SideBarMenuEntry]
    /// Holds the button on screen while the menu is up, so it does not vanish
    /// out from under the pointer when hover moves to the menu.
    @Binding var isMenuOpen: Bool
    var help: String = ""

    @State private var anchor: NSView?
    @State private var actions = MenuActionTarget()

    var body: some View {
        Button(action: present) {
            SymbolIcon("ellipsis", size: 14, weight: .semibold, color: GrokColor.sidebarInk)
                .rotationEffect(.degrees(90))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(GrokButtonStyle())
        .background(ViewAnchor(view: $anchor))
        .help(help)
    }

    private func present() {
        guard let anchor else { return }

        let menu = NSMenu()
        var hasDestructive = false

        for entry in entries {
            if entry.isDestructive, !hasDestructive, !menu.items.isEmpty {
                menu.addItem(.separator())
                hasDestructive = true
            }
            menu.addItem(actions.item(entry.title, entry.run))
        }

        isMenuOpen = true
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: anchor.bounds.height + 4),
            in: anchor
        )
        isMenuOpen = false
    }
}
