//
//  HeroHeader.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// The centred mark, headline and subtitle that opens every empty flow.
struct HeroHeader: View {
    let title: String
    let subtitle: String
    /// Shrinks the mark and headline on short windows so the composition
    /// still fits above the composer.
    var isCompact: Bool = false

    var body: some View {
        VStack(spacing: isCompact ? 10 : 14) {
            GrokMark(size: isCompact ? 68 : 100)

            VStack(spacing: isCompact ? 8 : 12) {
                Text(title)
                    .grokText(isCompact ? .title : .display, color: GrokColor.black1)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .grokText(isCompact ? .body : .lead, color: GrokColor.black6)
                    .multilineTextAlignment(.center)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Where a starter's glyph comes from: a catalog asset where the project
/// ships one, otherwise an SF Symbol.
enum StarterIcon {
    case asset(String)
    case symbol(String)
}

/// One of the 252×160 prompt starters below a hero.
struct SuggestionCard: View {
    let title: String
    let description: String
    let icon: StarterIcon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                glyph
                    .frame(height: 40, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .grokText(.subheading, color: GrokColor.black1)
                    Text(description)
                        .grokText(.footnote, color: GrokColor.black5)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .frame(height: GrokMetrics.cardSize.height)
            .hoverBackground(GrokColor.white4, hover: GrokColor.white2, cornerRadius: GrokMetrics.cardRadius)
            .decorativeBorder(GrokColor.white3, cornerRadius: GrokMetrics.cardRadius)
        }
        .buttonStyle(GrokButtonStyle())
    }

    @ViewBuilder
    private var glyph: some View {
        switch icon {
        case .asset(let name):
            GrokIcon(name, size: 34, color: GrokColor.black1)
        case .symbol(let name):
            SymbolIcon(name, size: 30, color: GrokColor.black1)
        }
    }
}

/// A suggestion card's content, so a flow can declare its starters as data.
struct SuggestionStarter: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: StarterIcon
    let prompt: String
}

/// The row of starters, wrapping onto a second line on narrow windows.
struct SuggestionRow: View {
    let starters: [SuggestionStarter]
    let availableWidth: CGFloat
    let onSelect: (SuggestionStarter) -> Void

    private var columns: [GridItem] {
        let fits = max(1, min(starters.count, Int(availableWidth / (GrokMetrics.cardSize.width + 24))))
        return Array(repeating: GridItem(.flexible(), spacing: 24), count: fits)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 24) {
            ForEach(starters) { starter in
                SuggestionCard(
                    title: starter.title,
                    description: starter.description,
                    icon: starter.icon
                ) {
                    onSelect(starter)
                }
            }
        }
        .frame(maxWidth: GrokMetrics.heroWidth)
    }
}
