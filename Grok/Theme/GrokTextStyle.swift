//
//  GrokTextStyle.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// A type ramp lifted straight from the design file.
///
/// The design is authored with explicit line heights; SwiftUI only exposes
/// line *spacing*, so each style converts its line height into the extra
/// leading the system font needs.
struct GrokTextStyle {
    let size: CGFloat
    let weight: Font.Weight
    let lineHeight: CGFloat

    var font: Font { .system(size: size, weight: weight) }

    /// SF renders at roughly 1.21× the point size, so the remainder of the
    /// designed line height becomes line spacing.
    var lineSpacing: CGFloat { max(0, lineHeight - size * 1.21) }

    // MARK: Display & headings

    static let display = GrokTextStyle(size: 44, weight: .bold, lineHeight: 54)
    static let title = GrokTextStyle(size: 28, weight: .bold, lineHeight: 36)
    static let sectionTitle = GrokTextStyle(size: 24, weight: .bold, lineHeight: 32)
    static let heading = GrokTextStyle(size: 20, weight: .medium, lineHeight: 30)
    static let subheading = GrokTextStyle(size: 18, weight: .medium, lineHeight: 30)
    static let upgradeTitle = GrokTextStyle(size: 14, weight: .bold, lineHeight: 20)
    static let upgradeAction = GrokTextStyle(size: 18, weight: .bold, lineHeight: 24)

    // MARK: Body

    /// Lead paragraph under a headline.
    static let lead = GrokTextStyle(size: 20, weight: .regular, lineHeight: 32)
    /// Chat bubbles, input text, list rows.
    static let body = GrokTextStyle(size: 16, weight: .regular, lineHeight: 24)
    /// Long-form assistant copy, which uses a looser measure.
    static let bodyRelaxed = GrokTextStyle(size: 16, weight: .regular, lineHeight: 28)
    static let bodyEmphasis = GrokTextStyle(size: 16, weight: .medium, lineHeight: 28)
    static let bodyMedium = GrokTextStyle(size: 16, weight: .medium, lineHeight: 24)

    // MARK: Controls & captions

    static let control = GrokTextStyle(size: 15, weight: .medium, lineHeight: 30)
    static let controlCompact = GrokTextStyle(size: 15, weight: .medium, lineHeight: 24)
    static let controlPlain = GrokTextStyle(size: 15, weight: .regular, lineHeight: 24)
    static let caption = GrokTextStyle(size: 14, weight: .regular, lineHeight: 22)
    static let footnote = GrokTextStyle(size: 13, weight: .regular, lineHeight: 22)
    static let footnoteMedium = GrokTextStyle(size: 13, weight: .medium, lineHeight: 22)
    static let label = GrokTextStyle(size: 12, weight: .medium, lineHeight: 24)
    static let labelPlain = GrokTextStyle(size: 12, weight: .regular, lineHeight: 24)
    static let micro = GrokTextStyle(size: 12, weight: .regular, lineHeight: 16)
    static let metadata = GrokTextStyle(size: 12, weight: .regular, lineHeight: 18)
    static let fileTitle = GrokTextStyle(size: 15, weight: .medium, lineHeight: 22)

    // MARK: Paywall
    //
    // The upgrade dialog is drawn a step larger than the rest of the app, so
    // it carries its own headline, price and button sizes.

    /// "More tools. More possibilities."
    static let paywallTitle = GrokTextStyle(size: 40, weight: .bold, lineHeight: 48)
    /// The headline figure on a plan card.
    static let paywallPrice = GrokTextStyle(size: 26, weight: .bold, lineHeight: 32)
    /// The call to action.
    static let paywallAction = GrokTextStyle(size: 17, weight: .medium, lineHeight: 24)
    /// A feature's name in the list beside the preview.
    static let paywallFeature = GrokTextStyle(size: 16, weight: .medium, lineHeight: 22)
    /// A feature's one-line explanation, the billing note, the period suffix.
    static let paywallDetail = GrokTextStyle(size: 13, weight: .regular, lineHeight: 20)
    /// "Most Popular" and "Best Value" on a plan card.
    static let paywallBadge = GrokTextStyle(size: 12, weight: .medium, lineHeight: 22)
    /// Terms, Privacy and Restore along the dialog's foot.
    static let paywallFootnote = GrokTextStyle(size: 12, weight: .regular, lineHeight: 20)
}

extension View {
    /// Applies a design-file text style: font, weight and designed leading.
    func grokText(_ style: GrokTextStyle, color: Color? = nil) -> some View {
        font(style.font)
            .lineSpacing(style.lineSpacing)
            .foregroundColor(color)
    }
}
