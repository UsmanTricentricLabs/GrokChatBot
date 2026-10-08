//
//  AttachmentViews.swift
//  Grok
//
//  Created by Tricentric Labs on 02/10/2026.
//

import AppKit
import SwiftUI

/// The attached files sitting above the prompt field, each removable.
struct AttachmentChipRow: View {
    let attachments: [ChatAttachment]
    var onRemove: ((ChatAttachment) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentChip(attachment: attachment) {
                        onRemove?(attachment)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 56)
    }
}

/// One file: its thumbnail or kind glyph, its name and size, and the control
/// that takes it back off the prompt.
struct AttachmentChip: View {
    let attachment: ChatAttachment
    var onRemove: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            thumbnail

            VStack(alignment: .leading, spacing: 0) {
                Text(attachment.name)
                    .grokText(.footnoteMedium, color: GrokColor.black1)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(attachment.subtitle)
                    .grokText(.metadata, color: GrokColor.black6)
                    .lineLimit(1)
            }
            .frame(maxWidth: 160, alignment: .leading)

            if let onRemove {
                Button(action: onRemove) {
                    SymbolIcon("xmark.circle.fill", size: 15, color: GrokColor.black6)
                }
                .buttonStyle(GrokButtonStyle())
                .opacity(isHovering ? 1 : 0.45)
                .help("attachment.remove".localized)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: GrokMetrics.chipRadius, style: .continuous)
                .fill(GrokColor.white1)
        )
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = attachment.previewData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(GrokColor.white3)
                .frame(width: 32, height: 32)
                .overlay(SymbolIcon(attachment.kind.symbolName, size: 15, color: GrokColor.black5))
        }
    }
}

/// The quiet row the composer shows when a file could not be attached.
struct AttachmentErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SymbolIcon("exclamationmark.triangle.fill", size: 14, color: GrokColor.error)
                .padding(.top, 2)

            Text(message)
                .grokText(.footnote, color: GrokColor.black3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                SymbolIcon("xmark", size: 11, weight: .semibold, color: GrokColor.black6)
            }
            .buttonStyle(GrokButtonStyle())
            .help("common.dismiss".localized)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: GrokMetrics.tileRadius, style: .continuous)
                .fill(GrokColor.errorTint)
        )
    }
}

/// The sheet a locked PDF raises. It stays open on a wrong password so the
/// user can try again without re-picking the file.
struct AttachmentPasswordSheet: View {
    let fileName: String
    /// Set after a failed attempt.
    let errorMessage: String?
    let isUnlocking: Bool
    let onUnlock: (String) -> Void
    let onCancel: () -> Void

    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("attachment.locked.title".localized)
                    .grokText(.subheading, color: GrokColor.black1)

                Text("attachment.locked.detail".localized(fileName))
                    .grokText(.caption, color: GrokColor.black6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .font(GrokTextStyle.body.font)
                .onSubmit(submit)

            if let errorMessage {
                Text(errorMessage)
                    .grokText(.footnote, color: GrokColor.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button(isUnlocking ? "Unlocking…" : "Unlock", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || isUnlocking)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(GrokColor.white2)
    }

    private func submit() {
        guard !password.isEmpty, !isUnlocking else { return }
        onUnlock(password)
    }
}

/// The attachments shown above a sent prompt, so the thread records what the
/// question was asked about.
struct MessageAttachmentRow: View {
    let attachments: [ChatAttachment]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(attachments) { attachment in
                AttachmentChip(attachment: attachment)
            }
        }
    }
}
