//
//  GrokControls.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// Strips the default button chrome and adds the subtle press feedback used
/// across the app.
struct GrokButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// Swaps the background on hover, the interaction pattern the design uses
    /// for every quiet control.
    func hoverBackground(
        _ resting: Color,
        hover: Color,
        cornerRadius: CGFloat
    ) -> some View {
        modifier(HoverBackground(resting: resting, hover: hover, cornerRadius: cornerRadius))
    }

    /// Draws a hairline border inside the view's bounds.
    ///
    /// Borders are decoration, so they never take clicks — an overlay that
    /// does will swallow taps meant for the control underneath.
    func decorativeBorder(
        _ color: Color,
        width: CGFloat = 1,
        cornerRadius: CGFloat,
        dash: [CGFloat] = []
    ) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(color, style: StrokeStyle(lineWidth: width, dash: dash))
                .allowsHitTesting(false)
        )
    }
}

private struct HoverBackground: ViewModifier {
    let resting: Color
    let hover: Color
    let cornerRadius: CGFloat
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovering ? hover : resting)
            )
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

/// A circular icon button that lights up on hover — message actions, the
/// summary toolbar and the image result row all use it.
struct CircularIconButton<Icon: View>: View {
    var diameter: CGFloat = 36
    var resting: Color = .clear
    var hover: Color = GrokColor.white4
    var help: String?
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            icon()
                .frame(width: diameter, height: diameter)
                .hoverBackground(resting, hover: hover, cornerRadius: diameter / 2)
        }
        .buttonStyle(GrokButtonStyle())
        .help(help ?? "")
    }
}

/// A circular icon button that confirms it ran: the glyph becomes a checkmark
/// for a moment after the action.
///
/// Copy is the case that needs this — the pasteboard gives no sign of its own
/// that anything happened, so without it the button looks inert.
struct ConfirmingIconButton<Idle: View>: View {
    var diameter: CGFloat = 36
    var resting: Color = .clear
    var hover: Color = GrokColor.white4
    var confirmationSize: CGFloat = 15
    var confirmationColor: Color = GrokColor.black1
    var help: String
    var confirmedHelp: String = "common.copied".localized
    /// How long the checkmark stays before the glyph returns.
    var duration: TimeInterval = 1.4
    let action: () -> Void
    @ViewBuilder let idle: () -> Idle

    @State private var isConfirmed = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            action()
            confirm()
        } label: {
            Group {
                if isConfirmed {
                    SymbolIcon(
                        "checkmark",
                        size: confirmationSize,
                        weight: .semibold,
                        color: confirmationColor
                    )
                } else {
                    idle()
                }
            }
            .frame(width: diameter, height: diameter)
            .hoverBackground(resting, hover: hover, cornerRadius: diameter / 2)
        }
        .buttonStyle(GrokButtonStyle())
        .help(isConfirmed ? confirmedHelp : help)
        .animation(.easeOut(duration: 0.15), value: isConfirmed)
        .onDisappear { resetTask?.cancel() }
    }

    /// Pressing again restarts the window rather than cutting it short.
    private func confirm() {
        isConfirmed = true
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            isConfirmed = false
        }
    }
}

/// A rounded capsule button with an optional leading glyph.
struct PillButton<Leading: View>: View {
    let title: String
    var style: GrokTextStyle = .control
    var height: CGFloat = 40
    var horizontalPadding: CGFloat = 16
    var background: Color = GrokColor.white1
    var hoverBackground: Color = GrokColor.white2
    var foreground: Color = GrokColor.black1
    let action: () -> Void
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                leading()
                Text(title)
                    .grokText(style, color: foreground)
                    .fixedSize()
            }
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .hoverBackground(background, hover: hoverBackground, cornerRadius: height / 2)
        }
        .buttonStyle(GrokButtonStyle())
    }
}

extension PillButton where Leading == EmptyView {
    init(
        title: String,
        style: GrokTextStyle = .control,
        height: CGFloat = 40,
        horizontalPadding: CGFloat = 16,
        background: Color = GrokColor.white1,
        hoverBackground: Color = GrokColor.white2,
        foreground: Color = GrokColor.black1,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            style: style,
            height: height,
            horizontalPadding: horizontalPadding,
            background: background,
            hoverBackground: hoverBackground,
            foreground: foreground,
            action: action,
            leading: { EmptyView() }
        )
    }
}

/// The inset segmented control used for summary length and aspect ratio.
struct GrokSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var height: CGFloat = 40
    var inset: CGFloat = 4
    var textStyle: GrokTextStyle = .caption
    var track: Color = GrokColor.white4
    var knob: Color = GrokColor.white1

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .grokText(textStyle, color: GrokColor.black1)
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .frame(height: height - inset * 2)
                        .background(
                            Capsule().fill(selection == option ? knob : .clear)
                        )
                }
                .buttonStyle(GrokButtonStyle())
            }
        }
        .padding(inset)
        .frame(height: height)
        .background(Capsule().fill(track))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}
