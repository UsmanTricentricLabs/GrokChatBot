//
//  GrokColor.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// Design tokens exported from the Figma file (`components/fig-tokens.css`).
///
/// Grok ships light-only — `AppDelegate` pins the app to Aqua — so each token
/// is the design file's light value. The export also defines a dark value for
/// every token here, which is where to start if dark mode is ever enabled.
enum GrokColor {

    // MARK: Surfaces (white ramp)

    /// Pure surface: pills, popovers, raised controls.
    static let white1 = Color(hex: 0xFFFFFF)
    /// Hover surface for controls that sit on a card.
    static let white2 = Color(hex: 0xF6F6F6)
    /// The main content canvas behind every screen.
    static let white3 = Color(hex: 0xEDEDED)
    /// Cards, bubbles and the input bar.
    static let white4 = Color(hex: 0xDBDBDB)
    /// Focus ring on the input bar.
    static let white5 = Color(hex: 0xC0C0C0)
    /// Muted glyphs and the idle send button.
    static let white6 = Color(hex: 0xA0A0A0)

    // MARK: Content (black ramp)

    /// Primary ink: headlines, body copy, active controls.
    static let black1 = Color(hex: 0x141414)
    static let black2 = Color(hex: 0x1F1F1F)
    static let black3 = Color(hex: 0x2E2E2E)
    static let black4 = Color(hex: 0x424242)
    /// Secondary copy inside cards.
    static let black5 = Color(hex: 0x5C5C5C)
    /// Tertiary copy: subtitles, captions, metadata.
    static let black6 = Color(hex: 0x707070)

    // MARK: Accents

    static let primary = Color(hex: 0x9177C7)
    static let error = Color(hex: 0xFC4142)
    static let errorTint = Color(hex: 0xFFEEED)

    // MARK: Sidebar

    /// The sidebar runs dark against the light canvas, matching the starfield
    /// plate it is composited over.
    static let sidebarBase = Color(hex: 0x707070)
    static let sidebarInk = Color.white
    static let sidebarMutedInk = Color(hex: 0xDBDBDB)
    static let sidebarSubtleInk = Color(hex: 0xA0A0A0)
    static let sidebarSelection = Color(hex: 0x1F1F1F)
    static let sidebarDivider = Color(hex: 0x5C5C5C)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
