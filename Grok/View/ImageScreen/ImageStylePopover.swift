//
//  ImageStylePopover.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// The popover that opens from the style pill: eight style chips and a
/// four-way aspect ratio switch.
struct ImageStylePopover: View {
    @Binding var style: ImageStyle
    @Binding var ratio: ImageAspectRatio

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Style")
                .grokText(.label, color: GrokColor.black6)
                .padding(.horizontal, 6)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(ImageStyle.allCases) { option in
                    StyleChip(style: option, isSelected: option == style) {
                        style = option
                    }
                }
            }

            Rectangle()
                .fill(GrokColor.white3)
                .frame(height: 1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)

            HStack(spacing: 8) {
                Text("Aspect ratio")
                    .grokText(.label, color: GrokColor.black6)
                    .padding(.leading, 6)
                Spacer(minLength: 8)
                GrokSegmentedControl(
                    options: ImageAspectRatio.allCases,
                    selection: $ratio,
                    title: \.title,
                    height: 36,
                    inset: 3,
                    textStyle: .footnote,
                    track: GrokColor.white3
                )
            }
        }
        .padding(12)
        .frame(width: 340)
    }
}

private struct StyleChip: View {
    let style: ImageStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                SymbolIcon(style.symbol, size: 15, color: foreground)
                Text(style.title)
                    .grokText(.caption, color: foreground)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .hoverBackground(
                isSelected ? GrokColor.black1 : GrokColor.white2,
                hover: isSelected ? GrokColor.black1 : GrokColor.white3,
                cornerRadius: GrokMetrics.chipRadius
            )
        }
        .buttonStyle(GrokButtonStyle())
    }

    private var foreground: Color {
        isSelected ? GrokColor.white1 : GrokColor.black1
    }
}
