//
//  SideBarView.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// The persistent navigation rail. Its middle slot changes with the active
/// flow: chat history, image thumbnails, documents or an empty state.
struct SideBarView: View {

    @ObservedObject var screenSwitchVM: ScreenSwitchViewModel
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var imageVM: ImageViewModel
    @ObservedObject var pdfVM: PDFViewModel
    var containerWidth: CGFloat
    var containerHeight: CGFloat
    /// The window's own traffic lights sit over the top-left of this rail, so
    /// the content is inset below them. An overlay drawer has no such chrome.
    var reservesTitleBarSpace: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SideBarNewChatButton(action: startNewChat)

            VStack(alignment: .leading, spacing: 4) {
                SideBarNavItem(
                    title: "Create Image",
                    asset: GrokAsset.createImage,
                    isSelected: screenSwitchVM.screen == .createImage
                ) {
                    // Like New Chat: the nav item opens a fresh canvas rather
                    // than returning to the last result.
                    imageVM.startNewImage()
                    screenSwitchVM.show(.createImage)
                }

                SideBarNavItem(
                    title: "PDF Summary",
                    asset: GrokAsset.pdfSummary,
                    isSelected: screenSwitchVM.screen == .pdfSummary
                ) {
                    // Like New Chat and Create Image: the nav item opens the
                    // empty drop zone rather than the last summary.
                    pdfVM.startNewSummary()
                    screenSwitchVM.show(.pdfSummary)
                }
            }

            Rectangle()
                .fill(GrokColor.sidebarDivider)
                .frame(height: 1)

            ScrollView(.vertical, showsIndicators: false) {
                historySlot
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            }

            SideBarUpgradeCard(action: {})
        }
        .padding(.horizontal, 12)
        .padding(.top, reservesTitleBarSpace ? GrokMetrics.trafficLightInset : 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SideBarBackground())
    }

    // MARK: Slots

    @ViewBuilder
    private var historySlot: some View {
        switch screenSwitchVM.screen {
        case .home:
            if chatVM.conversations.isEmpty {
                SideBarEmptyState(
                    title: "No chats yet!",
                    subtitle: "Conversations you start will show up here"
                )
                .padding(.top, 60)
            } else {
                SideBarHistory(label: "Chat", chatVM: chatVM)
            }

        case .createImage:
            if imageVM.hasHistory {
                SideBarImageHistory(imageVM: imageVM)
            } else {
                SideBarEmptyState(
                    title: "No images yet!",
                    subtitle: "Your creations will show up here"
                )
                .padding(.top, 60)
            }

        case .pdfSummary:
            if pdfVM.summarizedDocuments.isEmpty {
                SideBarEmptyState(
                    title: "No PDFs yet!",
                    subtitle: "Summaries you create will show up here"
                )
                .padding(.top, 60)
            } else {
                SideBarDocumentList(pdfVM: pdfVM)
            }
        }
    }

    private func startNewChat() {
        chatVM.startNewConversation()
        screenSwitchVM.show(.home)
    }
}

/// The "Documents" slot shown once at least one PDF has been summarized.
struct SideBarDocumentList: View {
    @ObservedObject var pdfVM: PDFViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Documents")
                .grokText(.label, color: GrokColor.sidebarInk)
                .frame(height: 24)
                .padding(.horizontal, 4)

            ForEach(pdfVM.summarizedDocuments) { document in
                SideBarDocumentRow(
                    document: document,
                    isSelected: document.url == pdfVM.document?.url,
                    pdfVM: pdfVM
                )
            }
        }
    }
}

/// One document row. Clicking it reopens that PDF's summary, the way a chat
/// row reopens its conversation.
struct SideBarDocumentRow: View {
    let document: PDFDocumentInfo
    let isSelected: Bool
    @ObservedObject var pdfVM: PDFViewModel

    @State private var isHovering = false

    var body: some View {
        Button {
            pdfVM.select(document)
        } label: {
            HStack(spacing: 0) {
                Text(document.name)
                    .grokText(.labelPlain, color: GrokColor.sidebarInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Capsule().fill(background))
            .contentShape(Capsule())
        }
        .buttonStyle(GrokButtonStyle())
        .help(document.name)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var background: Color {
        if isSelected { return GrokColor.sidebarSelection }
        return isHovering ? Color.white.opacity(0.08) : .clear
    }
}
