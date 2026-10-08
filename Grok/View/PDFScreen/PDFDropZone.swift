//
//  PDFDropZone.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// The upload target. It takes the prompt cards' footprint and changes its
/// border and fill while a file is dragged over it.
struct PDFDropZone: View {
    let isTargeted: Bool
    let draggedFileName: String?
    let onChooseFile: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(isTargeted ? GrokColor.black1 : GrokColor.white2)
                    SymbolIcon(
                        isTargeted ? "arrow.down" : "arrow.up.doc",
                        size: 20,
                        color: isTargeted ? GrokColor.white1 : GrokColor.black1
                    )
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 0) {
                    Text(isTargeted ? "pdf.drop.release".localized : "pdf.drop.idle".localized)
                        .grokText(.subheading, color: GrokColor.black1)
                    Text(subtitle)
                        .grokText(.footnote, color: GrokColor.black5)
                        .lineLimit(1)
                }
            }

            if !isTargeted {
                PillButton(
                    title: "pdf.chooseFile".localized,
                    background: GrokColor.white1,
                    hoverBackground: GrokColor.white2,
                    action: onChooseFile
                )
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background(
            RoundedRectangle(cornerRadius: GrokMetrics.cardRadius, style: .continuous)
                .fill(isTargeted ? GrokColor.white2 : GrokColor.white4)
        )
        .decorativeBorder(
            isTargeted ? GrokColor.black1 : GrokColor.white6,
            width: 1.5,
            cornerRadius: GrokMetrics.cardRadius,
            dash: [6, 5]
        )
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }

    private var subtitle: String {
        if isTargeted, let draggedFileName { return draggedFileName }
        return isTargeted ? "pdf.drop.releaseHint".localized : "pdf.drop.limit".localized(FileImportLimits.formattedByteLimit)
    }
}

/// The selected-file row, reused by the error state with a tinted icon tile.
struct PDFFileRow: View {
    let title: String
    let subtitle: String
    var isError: Bool = false
    /// The glyph in the tinted tile. Defaults to the warning triangle, since a
    /// failure here is as likely to be a damaged or oversized file as a locked
    /// one.
    var errorSymbol: String = "exclamationmark.triangle.fill"
    var primaryActionTitle: String
    let onPrimaryAction: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isError ? GrokColor.errorTint : GrokColor.white2)
                SymbolIcon(
                    isError ? errorSymbol : "doc.richtext",
                    size: 22,
                    color: isError ? GrokColor.error : GrokColor.black1
                )
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .grokText(.subheading, color: GrokColor.black1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .grokText(.footnote, color: GrokColor.black5)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PillButton(
                title: primaryActionTitle,
                background: isError ? GrokColor.white1 : GrokColor.white2,
                hoverBackground: GrokColor.white1,
                action: onPrimaryAction
            )

            CircularIconButton(
                diameter: 40,
                resting: GrokColor.white2,
                hover: GrokColor.white1,
                help: "common.remove".localized,
                action: onRemove
            ) {
                SymbolIcon("xmark", size: 15, color: GrokColor.black1)
            }
        }
        .padding(16)
        .frame(minHeight: 88)
        .background(
            RoundedRectangle(cornerRadius: GrokMetrics.cardRadius, style: .continuous)
                .fill(GrokColor.white4)
        )
        .decorativeBorder(GrokColor.white3, cornerRadius: GrokMetrics.cardRadius)
    }
}
