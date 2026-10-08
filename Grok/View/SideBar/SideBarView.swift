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
    /// Opens the paywall. The rail does not present it itself — the dialog
    /// covers the whole shell, so it belongs to the shell.
    var onUpgrade: () -> Void = {}

    /// Subscription state comes from the manager rather than a copy kept here,
    /// so the upgrade card disappears the moment a purchase or a restore lands.
    @ObservedObject private var iap = IAPManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SideBarNewChatButton(action: startNewChat)

            VStack(alignment: .leading, spacing: 4) {
                SideBarNavItem(
                    title: "feature.image.title".localized,
                    asset: GrokAsset.createImage,
                    isSelected: screenSwitchVM.screen == .createImage
                ) {
                    // Like New Chat: the nav item opens a fresh canvas rather
                    // than returning to the last result.
                    imageVM.startNewImage()
                    screenSwitchVM.show(.createImage)
                }

                SideBarNavItem(
                    title: "feature.pdf.title".localized,
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

            // Promotional, so it is only for customers who have something to
            // buy. A subscriber keeps the space for their history instead.
            if !iap.isPremiumUnlocked {
                SideBarUpgradeCard(action: onUpgrade)
            }
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
                    title: "sidebar.empty.chats.title".localized,
                    subtitle: "sidebar.empty.chats.subtitle".localized
                )
                .padding(.top, 60)
            } else {
                SideBarHistory(label: "sidebar.section.chat".localized, chatVM: chatVM)
            }

        case .createImage:
            if imageVM.hasHistory {
                SideBarImageHistory(imageVM: imageVM)
            } else {
                SideBarEmptyState(
                    title: "sidebar.empty.images.title".localized,
                    subtitle: "sidebar.empty.images.subtitle".localized
                )
                .padding(.top, 60)
            }

        case .pdfSummary:
            if pdfVM.summarizedDocuments.isEmpty {
                SideBarEmptyState(
                    title: "sidebar.empty.pdfs.title".localized,
                    subtitle: "sidebar.empty.pdfs.subtitle".localized
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
            Text("sidebar.section.documents".localized)
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

    /// Kept up while the menu is open, so the row does not drop its button the
    /// moment the pointer leaves it for the menu.
    @State private var isMenuOpen = false

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
            .padding(.leading, 14)
            // Room for the menu button, so a long name is truncated rather
            // than running underneath it.
            .padding(.trailing, 34)
            .frame(height: 36)
            .background(Capsule().fill(background))
            .contentShape(Capsule())
        }
        .buttonStyle(GrokButtonStyle())
        .help(document.name)
        .overlay(alignment: .trailing) {
            if isHovering || isMenuOpen {
                SideBarRowMenu(
                    entries: [
                        SideBarMenuEntry(title: "common.delete".localized, isDestructive: true) {
                            pdfVM.delete(document)
                        }
                    ],
                    isMenuOpen: $isMenuOpen,
                    help: "sidebar.documentOptions".localized
                )
                .padding(.trailing, 8)
            }
        }
        // Right-clicking the row does the same thing, which is what the Finder
        // habit reaches for first.
        .contextMenu {
            Button("common.delete".localized, role: .destructive) {
                pdfVM.delete(document)
            }
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var background: Color {
        if isSelected { return GrokColor.sidebarSelection }
        return isHovering ? Color.white.opacity(0.08) : .clear
    }
}
