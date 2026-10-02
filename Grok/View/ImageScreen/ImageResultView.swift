//
//  ImageResultView.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import AppKit
import SwiftUI

/// The 16:9 (or chosen ratio) frame that shimmers while an image renders.
struct ImageGeneratingView: View {
    let image: GeneratedImage

    var body: some View {
        ZStack {
            GrokColor.white4
            ShimmerOverlay()

            VStack(spacing: 6) {
                SymbolIcon("sparkles", size: 26, color: GrokColor.black5)
                    .padding(.bottom, 6)
                Text("Creating your image")
                    .grokText(.bodyMedium, color: GrokColor.black1)
                Text("\(image.styleCaption) · about 10 seconds")
                    .grokText(.footnote, color: GrokColor.black5)
            }
        }
        .mediaFrame(ratio: image.ratio.value)
        .clipShape(RoundedRectangle(cornerRadius: GrokMetrics.cardRadius, style: .continuous))
        .decorativeBorder(GrokColor.white3, cornerRadius: GrokMetrics.cardRadius)
    }
}

/// A finished image with its caption and the five quiet actions beneath it.
struct ImageResultView: View {
    let image: GeneratedImage
    @ObservedObject var imageVM: ImageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeneratedImageView(image: image)
                .mediaFrame(ratio: image.ratio.value)
                .clipShape(RoundedRectangle(cornerRadius: GrokMetrics.cardRadius, style: .continuous))

            // A tall ratio renders a narrow image, and the caption and the
            // five actions cannot share that measure — side by side they
            // squeeze the caption down to one letter per line. Below the
            // breakpoint the row stacks instead.
            if isStacked {
                VStack(alignment: .leading, spacing: 6) {
                    caption
                    actionRow
                }
                .frame(maxWidth: captionWidth, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    caption
                    Spacer(minLength: 12)
                    actionRow
                }
                .frame(maxWidth: captionWidth)
            }
        }
    }

    // MARK: Slots

    private var caption: some View {
        Text(image.styleCaption)
            .grokText(.footnote, color: GrokColor.black6)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, 4)
    }

    private var actionRow: some View {
        HStack(spacing: 2) {
            action("square.and.arrow.down", help: "Save") { imageVM.save(image) }
            ConfirmingIconButton(
                diameter: 32,
                confirmationSize: 15,
                help: "Copy",
                action: { imageVM.copy(image) }
            ) {
                SymbolIcon("doc.on.doc", size: 16, color: GrokColor.black5)
            }
            ShareAction { view in imageVM.share(image, from: view) }
            action("arrow.clockwise", help: "Regenerate") { imageVM.regenerate(image) }
            action("pencil", help: "Edit prompt") { imageVM.editPrompt(for: image) }
        }
    }

    // MARK: Layout

    /// The caption tracks the rendered media rather than the full column.
    private var captionWidth: CGFloat {
        min(GrokMetrics.mediaWidth, GrokMetrics.mediaMaxHeight * image.ratio.value)
    }

    /// Five 32pt buttons and the gaps between them.
    private static let actionRowWidth: CGFloat = 5 * 32 + 4 * 2

    /// The measure the caption needs beside the actions before it starts
    /// breaking mid-word.
    private static let minimumCaptionWidth: CGFloat = 140

    private var isStacked: Bool {
        captionWidth < Self.actionRowWidth + Self.minimumCaptionWidth
    }

    private func action(_ symbol: String, help: String, perform: @escaping () -> Void) -> some View {
        CircularIconButton(diameter: 32, help: help, action: perform) {
            SymbolIcon(symbol, size: 16, color: GrokColor.black5)
        }
    }
}

extension View {
    /// Sizes generated media to the designed measure, capped in both
    /// directions so every aspect ratio fits the column.
    func mediaFrame(ratio: CGFloat) -> some View {
        frame(
            maxWidth: min(GrokMetrics.mediaWidth, GrokMetrics.mediaMaxHeight * ratio),
            maxHeight: GrokMetrics.mediaMaxHeight
        )
        .aspectRatio(ratio, contentMode: .fit)
    }
}

/// Share needs a view to anchor the system picker, which AppKit supplies.
struct ShareAction: View {
    let perform: (NSView?) -> Void
    @State private var anchor: NSView?

    var body: some View {
        CircularIconButton(diameter: 32, help: "Share", action: { perform(anchor) }) {
            SymbolIcon("square.and.arrow.up", size: 16, color: GrokColor.black5)
        }
        .background(ViewAnchor(view: $anchor))
    }
}

/// Captures the backing `NSView` so AppKit pickers have somewhere to attach.
struct ViewAnchor: NSViewRepresentable {
    @Binding var view: NSView?

    func makeNSView(context: Context) -> NSView {
        let nsView = NSView()
        DispatchQueue.main.async { view = nsView }
        return nsView
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
