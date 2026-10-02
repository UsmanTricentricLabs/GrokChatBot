//
//  MessageViews.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// The right-aligned prompt bubble.
struct UserMessageBubble: View {
    let text: String
    /// Files sent with the prompt, shown above it so the thread records what
    /// the question was asked about.
    var attachments: [ChatAttachment] = []

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if !attachments.isEmpty {
                MessageAttachmentRow(attachments: attachments)
            }

            Text(text)
                .grokText(.body, color: GrokColor.black1)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(GrokColor.white4)
                )
        }
        .frame(maxWidth: GrokMetrics.bubbleMaxWidth, alignment: .trailing)
    }
}

/// The assistant answer slot. It renders the thinking label, the streaming
/// text with its caret, the finished blocks with actions, or the error row.
struct AssistantMessageView: View {
    let message: ChatMessage
    let onCopy: () -> Void
    let onSpeak: () -> Void
    let onRegenerate: () -> Void
    let onRetry: () -> Void

    var body: some View {
        switch message.state {
        case .thinking:
            HStack(spacing: 10) {
                GrokMark(size: 22)
                ShimmerText(text: "Thinking")
            }
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)

        case .failed(let failure):
            ErrorAnswerView(failure: failure, onRetry: onRetry)

        case .streaming, .complete:
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(message.blocks.enumerated()), id: \.offset) { index, block in
                    ResponseBlockView(
                        block: block,
                        showsCaret: message.state == .streaming && index == message.blocks.count - 1
                    )
                }

                if message.state == .complete {
                    MessageActionRow(
                        onCopy: onCopy,
                        onSpeak: onSpeak,
                        onRegenerate: onRegenerate
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A paragraph or a numbered list, with the medium-weight lead the design uses.
struct ResponseBlockView: View {
    let block: ResponseBlock
    var showsCaret: Bool = false

    var body: some View {
        switch block {
        case .paragraph(let text):
            StreamingParagraph(text: text, showsCaret: showsCaret)

        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1).")
                            .grokText(.bodyRelaxed, color: GrokColor.black6)
                            .frame(width: 18, alignment: .leading)

                        (
                            Text(item.lead).font(GrokTextStyle.bodyEmphasis.font)
                            + Text(" " + item.body).font(GrokTextStyle.bodyRelaxed.font)
                        )
                        .lineSpacing(GrokTextStyle.bodyRelaxed.lineSpacing)
                        .foregroundColor(GrokColor.black1)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// Copy · Read aloud · Regenerate, shown under a finished answer.
struct MessageActionRow: View {
    let onCopy: () -> Void
    let onSpeak: () -> Void
    let onRegenerate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ConfirmingIconButton(
                diameter: 20,
                hover: .clear,
                confirmationSize: 13,
                help: "Copy",
                action: onCopy
            ) {
                GrokIcon(GrokAsset.copy, size: 16, color: GrokColor.white6)
            }
            action(GrokAsset.speaker, size: 17, help: "Read aloud", action: onSpeak)
            action(GrokAsset.regenerate, size: 17, help: "Regenerate", action: onRegenerate)
        }
        .frame(height: 20)
    }

    private func action(_ asset: String, size: CGFloat, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            GrokIcon(asset, size: size, color: GrokColor.white6)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(GrokButtonStyle())
        .help(help)
    }
}

/// The quiet failure row: one red glyph, a plain sentence and Try Again.
struct ErrorAnswerView: View {
    let failure: AIErrorPresentation
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                SymbolIcon("exclamationmark.circle.fill", size: 18, color: GrokColor.error)
                    .frame(height: 28)

                VStack(alignment: .leading, spacing: 0) {
                    Text(failure.title)
                        .grokText(.bodyRelaxed, color: GrokColor.black1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(failure.detail)
                        .grokText(.caption, color: GrokColor.black6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Budget, subscription and credential failures will not resolve by
            // trying again, so the recovery action is offered only when it can
            // actually help.
            if failure.isRetryable {
                PillButton(
                    title: "Try Again",
                    style: .body,
                    height: 36,
                    horizontalPadding: 14,
                    background: GrokColor.white4,
                    hoverBackground: GrokColor.white2,
                    action: onRetry
                ) {
                    GrokIcon(GrokAsset.regenerate, size: 16, color: GrokColor.black1)
                }
                .padding(.leading, 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
