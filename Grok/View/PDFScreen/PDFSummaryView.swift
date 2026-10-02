//
//  PDFSummaryView.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// The finished summary: a slim file bar above a reading column of summary,
/// key points and the sections worth jumping to.
struct PDFSummaryView: View {
    let document: PDFDocumentInfo
    let summary: PDFSummary
    @ObservedObject var pdfVM: PDFViewModel

    var body: some View {
        VStack(spacing: 0) {
            fileBar
                .padding(.horizontal, GrokMetrics.contentPadding)

            ScrollViewReader { scroller in
                ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 32) {
                    section(title: "Summary") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(summary.title)
                                .grokText(.title, color: GrokColor.black1)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(summary.overview)
                                .grokText(.bodyRelaxed, color: GrokColor.black1)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Key Points")
                            .grokText(.subheading, color: GrokColor.black1)

                        ForEach(Array(summary.keyPoints.enumerated()), id: \.offset) { index, point in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1).")
                                    .grokText(.bodyRelaxed, color: GrokColor.black6)
                                    .frame(width: 18, alignment: .leading)
                                Text(point)
                                    .grokText(.bodyRelaxed, color: GrokColor.black1)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if !summary.sections.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Important Sections")
                                .grokText(.subheading, color: GrokColor.black1)

                            ForEach(summary.sections) { section in
                                HStack {
                                    Text(section.title)
                                        .grokText(.body, color: GrokColor.black1)
                                        .lineLimit(1)
                                    Spacer(minLength: 12)
                                    Text(section.pageLabel)
                                        .grokText(.caption, color: GrokColor.black6)
                                }
                                .frame(height: 48)
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(GrokColor.white4)
                                        .frame(height: 1)
                                }
                            }
                        }
                    }

                    if !pdfVM.followUps.isEmpty {
                        VStack(alignment: .trailing, spacing: 16) {
                            ForEach(pdfVM.followUps) { message in
                                followUpRow(message)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                .frame(maxWidth: GrokMetrics.readingWidth, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, 28)
                .padding(.bottom, 140)
                .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: pdfVM.followUps) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        scroller.scrollTo(Self.bottomID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private static let bottomID = "pdf-summary-bottom"


    @ViewBuilder
    private func followUpRow(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            UserMessageBubble(text: message.text)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant:
            AssistantMessageView(
                message: message,
                onCopy: { pdfVM.copy(message) },
                onSpeak: { pdfVM.speak(message) },
                onRegenerate: pdfVM.stopFollowUp,
                onRetry: pdfVM.stopFollowUp
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var fileBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: GrokMetrics.chipRadius, style: .continuous)
                    .fill(GrokColor.white4)
                SymbolIcon("doc.richtext", size: 19, color: GrokColor.black1)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 0) {
                Text(document.name)
                    .grokText(.fileTitle, color: GrokColor.black1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(document.subtitle) · Summarized just now")
                    .grokText(.metadata, color: GrokColor.black6)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                ConfirmingIconButton(
                    resting: GrokColor.white4,
                    hover: GrokColor.white2,
                    help: "Copy summary",
                    action: pdfVM.copySummary
                ) {
                    GrokIcon(GrokAsset.copy, size: 16, color: GrokColor.black1)
                }

                ShareAction { view in pdfVM.share(from: view) }

                PillButton(
                    title: "New PDF",
                    style: .controlCompact,
                    height: 36,
                    horizontalPadding: 14,
                    action: pdfVM.startNewDocument
                ) {
                    SymbolIcon("plus", size: 14, weight: .medium, color: GrokColor.black1)
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(GrokColor.white4)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .grokText(.footnoteMedium, color: GrokColor.black6)
            content()
        }
    }
}

/// The reading indicator shown while a document is consumed.
struct PDFProcessingView: View {
    let document: PDFDocumentInfo
    let progress: Double
    let statusLabel: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(GrokColor.white4)
                SymbolIcon("doc.richtext", size: 28, color: GrokColor.black1)
            }
            .frame(width: 72, height: 72)
            .decorativeBorder(GrokColor.white3, cornerRadius: 22)

            VStack(spacing: 4) {
                Text(document.name)
                    .grokText(.heading, color: GrokColor.black1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(statusLabel)
                    .grokText(.body, color: GrokColor.black6)
            }

            GrokProgressBar(progress: progress)

            PillButton(
                title: "Cancel",
                style: .controlPlain,
                height: 36,
                background: GrokColor.white4,
                hoverBackground: GrokColor.white2,
                action: onCancel
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
