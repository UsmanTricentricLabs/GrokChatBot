//
//  PDFScreen.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI
import UniformTypeIdentifiers

/// The PDF Summary flow: upload, inspect, process, read — with follow-up
/// questions once a summary exists.
struct PDFScreen: View {

    @ObservedObject var screenSwitchVM: ScreenSwitchViewModel
    @ObservedObject var pdfVM: PDFViewModel
    var containerWidth: CGFloat
    var containerHeight: CGFloat
    var showsSidebarToggle: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(showsSidebarToggle: showsSidebarToggle) {
                screenSwitchVM.isSidebarPresented.toggle()
            }

            ZStack(alignment: .bottom) {
                content

                if case .summarized = pdfVM.state {
                    PromptInputBarContainer {
                        PromptInputBar(
                            text: $pdfVM.followUpDraft,
                            placeholder: "pdf.askPlaceholder".localized,
                            onSubmit: pdfVM.askFollowUp
                        ) {
                            HStack(spacing: 6) {
                                MicrophoneButton(text: $pdfVM.followUpDraft)
                                SendButton(
                                    isEnabled: pdfVM.canAskFollowUp,
                                    isStreaming: pdfVM.isAnsweringFollowUp
                                ) {
                                    if pdfVM.isAnsweringFollowUp {
                                        pdfVM.stopFollowUp()
                                    } else {
                                        pdfVM.askFollowUp()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(GrokColor.white3)
        .onDrop(of: [UTType.fileURL], isTargeted: dropTarget) { providers in
            pdfVM.handleDrop(providers)
        }
        .sheet(item: $pdfVM.passwordRequest) { request in
            AttachmentPasswordSheet(
                fileName: request.name,
                errorMessage: request.errorMessage,
                isUnlocking: request.isUnlocking,
                onUnlock: pdfVM.submitPassword,
                onCancel: pdfVM.cancelPasswordRequest
            )
        }
    }

    // MARK: Slots

    @ViewBuilder
    private var content: some View {
        switch pdfVM.state {
        case .processing(let document):
            PDFProcessingView(
                document: document,
                progress: pdfVM.progress,
                statusLabel: pdfVM.progressLabel,
                onCancel: pdfVM.cancelSummarizing
            )

        case .summarized(let document, let summary):
            PDFSummaryView(document: document, summary: summary, pdfVM: pdfVM)

        default:
            hero
        }
    }

    private var hero: some View {
        CenteredScrollView(bottomInset: 60) {
            VStack(spacing: isCompact ? 32 : 60) {
                HeroHeader(
                    title: "pdf.hero.title".localized,
                    subtitle: "pdf.hero.subtitle".localized,
                    isCompact: isCompact
                )

                uploadSlot
                    .frame(maxWidth: GrokMetrics.heroWidth)
            }
        }
    }

    /// Short windows tighten the hero so the drop zone stays fully visible.
    private var isCompact: Bool {
        containerHeight < 700
    }

    @ViewBuilder
    private var uploadSlot: some View {
        switch pdfVM.state {
        case .empty:
            PDFDropZone(isTargeted: false, draggedFileName: nil, onChooseFile: pdfVM.chooseFile)

        case .dragging(let fileName):
            PDFDropZone(isTargeted: true, draggedFileName: fileName, onChooseFile: pdfVM.chooseFile)

        case .selected(let document):
            VStack(spacing: 16) {
                PDFFileRow(
                    title: document.name,
                    subtitle: document.subtitle,
                    primaryActionTitle: "Replace",
                    onPrimaryAction: pdfVM.chooseFile,
                    onRemove: pdfVM.removeDocument
                )

                HStack(spacing: 12) {
                    Text("pdf.length".localized)
                        .grokText(.caption, color: GrokColor.black6)
                        .padding(.leading, 16)

                    GrokSegmentedControl(
                        options: SummaryLength.allCases,
                        selection: $pdfVM.length,
                        title: \.title
                    )

                    Spacer(minLength: 12)

                    Button(action: pdfVM.summarize) {
                        HStack(spacing: 8) {
                            SymbolIcon("sparkles", size: 16, color: .white)
                            Text("pdf.summarize".localized)
                                .grokText(.bodyMedium, color: .white)
                                .fixedSize()
                        }
                        .padding(.leading, 20)
                        .padding(.trailing, 24)
                        .frame(height: GrokMetrics.inputButton)
                        .background(Capsule().fill(GrokColor.black1))
                    }
                    .buttonStyle(GrokButtonStyle())
                }
            }

        case .failed(let fileName, let reason):
            PDFFileRow(
                title: fileName,
                subtitle: reason,
                isError: true,
                primaryActionTitle: "Choose Another File",
                onPrimaryAction: pdfVM.chooseFile,
                onRemove: pdfVM.removeDocument
            )

        case .processing, .summarized:
            EmptyView()
        }
    }

    /// Only the upload states react to a drag, so a finished summary is not
    /// disturbed by a stray drop.
    private var dropTarget: Binding<Bool> {
        Binding(
            get: {
                if case .dragging = pdfVM.state { return true }
                return false
            },
            set: { pdfVM.setDragging($0) }
        )
    }
}
