//
//  GrokIcons.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// A vector asset drawn as a tintable glyph.
///
/// Most catalog assets are single-colour outlines, so they are rendered as
/// templates and take the colour the design calls for.
struct GrokIcon: View {
    let name: String
    var size: CGFloat
    var color: Color

    init(_ name: String, size: CGFloat = 20, color: Color = GrokColor.black1) {
        self.name = name
        self.size = size
        self.color = color
    }

    var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundColor(color)
    }
}

/// A vector asset that already carries its own plate — the attach,
/// microphone and send buttons, each authored as a filled circle with a glyph
/// punched out of it, at the design's light tones.
struct GrokPlateIcon: View {
    let name: String
    var size: CGFloat

    init(_ name: String, size: CGFloat) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// The Grok mark. Sized for the hero (100pt) and the streaming answer slot (22pt).
struct GrokMark: View {
    var size: CGFloat = 100
    var color: Color = GrokColor.black1

    var body: some View {
        GrokIcon(GrokAsset.mark, size: size, color: color)
    }
}

/// An SF Symbol at a design-file weight. Used for the glyphs the catalog
/// does not ship (chevrons, search, close, document and media symbols).
struct SymbolIcon: View {
    let name: String
    var size: CGFloat
    var weight: Font.Weight
    var color: Color

    init(_ name: String, size: CGFloat = 18, weight: Font.Weight = .regular, color: Color = GrokColor.black1) {
        self.name = name
        self.size = size
        self.weight = weight
        self.color = color
    }

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size, weight: weight))
            .foregroundColor(color)
    }
}
