//
//  GrokLoadingViews.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI
internal import Combine

/// Text with a highlight travelling across it — the "Thinking" label that
/// holds the answer slot before the first token arrives.
struct ShimmerText: View {
    let text: String
    var style: GrokTextStyle = .body
    @State private var phase: CGFloat = -1

    var body: some View {
        Text(text)
            .grokText(style)
            .overlay(
                LinearGradient(
                    colors: [GrokColor.white6, GrokColor.black1, GrokColor.white6],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 220)
                .offset(x: phase * 220)
                .mask(Text(text).grokText(style))
            )
            .mask(Text(text).grokText(style))
            .onAppear {
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
    }
}

/// A paragraph that carries a blinking caret after its last character while
/// the response is still streaming.
///
/// The caret is part of the string rather than a sibling view so it follows
/// the text as it wraps, instead of pinning to the edge of the line box.
struct StreamingParagraph: View {
    let text: String
    var style: GrokTextStyle = .bodyRelaxed
    var showsCaret: Bool

    @State private var isCaretVisible = true
    private let blink = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(text + caret)
            .grokText(style, color: GrokColor.black1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onReceive(blink) { _ in
                guard showsCaret else { return }
                isCaretVisible.toggle()
            }
    }

    /// A zero-width-looking spacer keeps the line length steady between blinks.
    private var caret: String {
        guard showsCaret else { return "" }
        return isCaretVisible ? "\u{258F}" : "\u{2007}"
    }
}

/// A diagonal sheen sweeping across a placeholder surface, used while an
/// image renders at its final size.
struct ShimmerOverlay: View {
    @State private var offset: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                stops: [
                    .init(color: GrokColor.white2.opacity(0), location: 0),
                    .init(color: GrokColor.white2.opacity(0.75), location: 0.5),
                    .init(color: GrokColor.white2.opacity(0), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: proxy.size.width * 0.7)
            .offset(x: offset * proxy.size.width * 1.4)
            .onAppear {
                withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                    offset = 1.2
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// An indeterminate spinner at the design's weight, used inside the pending
/// thumbnail tile.
struct GrokSpinner: View {
    var size: CGFloat = 22
    var color: Color = GrokColor.white4
    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.92)
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}

/// The thin determinate bar shown while a PDF is being read.
struct GrokProgressBar: View {
    let progress: Double
    var width: CGFloat = 320

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(GrokColor.white4)
            Capsule()
                .fill(GrokColor.black1)
                .frame(width: width * min(max(progress, 0), 1))
        }
        .frame(width: width, height: 4)
        .animation(.easeOut(duration: 0.25), value: progress)
    }
}
