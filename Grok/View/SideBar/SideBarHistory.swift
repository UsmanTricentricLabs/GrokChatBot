//
//  SideBarHistory.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// The titled history slot: a label with a search affordance, or the search
/// field once it is open, followed by the matching rows.
struct SideBarHistory: View {
    let label: String
    @ObservedObject var chatVM: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if chatVM.isSearching {
                SideBarSearchField(
                    query: $chatVM.searchQuery,
                    onDismiss: chatVM.toggleSearch
                )
                Text(resultsLabel)
                    .grokText(.labelPlain, color: GrokColor.sidebarMutedInk)
                    .padding(.horizontal, 6)
            } else {
                HStack(spacing: 0) {
                    Text(label)
                        .grokText(.label, color: GrokColor.sidebarInk)
                    Spacer(minLength: 0)
                    Button(action: chatVM.toggleSearch) {
                        SymbolIcon("magnifyingglass", size: 14, color: GrokColor.sidebarMutedInk)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(GrokButtonStyle())
                    .help("Search chats")
                }
                .frame(height: 24)
                .padding(.horizontal, 4)
            }

            if chatVM.visibleConversations.isEmpty {
                Text(chatVM.isSearching ? "No matches" : "No chats yet")
                    .grokText(.labelPlain, color: GrokColor.sidebarSubtleInk)
                    .padding(.horizontal, 14)
            } else {
                ForEach(chatVM.visibleConversations) { conversation in
                    SideBarConversationRow(
                        conversation: conversation,
                        isSelected: conversation.id == chatVM.selectedConversationID,
                        showsMenu: !chatVM.isSearching,
                        chatVM: chatVM
                    )
                }
            }
        }
    }

    private var resultsLabel: String {
        let count = chatVM.visibleConversations.count
        return "\(count) result\(count == 1 ? "" : "s")"
    }
}

/// One conversation row, with the ⋮ menu the design opens on the selected chat.
///
/// Selection is a button filling the row, with the menu laid over its trailing
/// edge so the two controls never compete for the same click.
struct SideBarConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let showsMenu: Bool
    @ObservedObject var chatVM: ChatViewModel

    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var draftTitle = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                chatVM.select(conversation)
            } label: {
                HStack(spacing: 10) {
                    title
                    Spacer(minLength: 0)
                    if conversation.isPinned {
                        SymbolIcon("pin.fill", size: 10, color: GrokColor.sidebarMutedInk)
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, showsMenu ? 32 : 10)
                .frame(height: 36)
                .background(Capsule().fill(background))
                .contentShape(Capsule())
            }
            .buttonStyle(GrokButtonStyle())

            if showsMenu, isSelected || isHovering {
                SideBarConversationMenu(conversation: conversation, chatVM: chatVM) {
                    draftTitle = conversation.title
                    isRenaming = true
                }
                .padding(.trailing, 10)
            }
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    @ViewBuilder
    private var title: some View {
        if isRenaming {
            TextField("", text: $draftTitle, onCommit: commitRename)
                .textFieldStyle(.plain)
                .grokText(.labelPlain, color: GrokColor.sidebarInk)
                .focused($isTitleFocused)
                .onExitCommand { isRenaming = false }
                .onAppear {
                    DispatchQueue.main.async { isTitleFocused = true }
                }
        } else {
            Text(conversation.title)
                .grokText(.labelPlain, color: GrokColor.sidebarInk)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var background: Color {
        if isSelected { return GrokColor.sidebarSelection }
        return isHovering ? Color.white.opacity(0.08) : .clear
    }

    private func commitRename() {
        chatVM.rename(conversation, to: draftTitle)
        isRenaming = false
        isTitleFocused = false
    }
}

/// Rename · Pin · Share, then Delete below a divider.
struct SideBarConversationMenu: View {
    let conversation: Conversation
    @ObservedObject var chatVM: ChatViewModel
    let onRename: () -> Void

    var body: some View {
        Menu {
            Button("Rename", action: onRename)
            Button(conversation.isPinned ? "Unpin" : "Pin") { chatVM.togglePin(conversation) }
            Button("Share") { chatVM.share(conversation) }
            Divider()
            Button("Delete", role: .destructive) { chatVM.delete(conversation) }
        } label: {
            SymbolIcon("ellipsis", size: 14, weight: .semibold, color: GrokColor.sidebarInk)
                .rotationEffect(.degrees(90))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 16, height: 16)
        .fixedSize()
    }
}

/// The inline search field that replaces the "Chat" label.
struct SideBarSearchField: View {
    @Binding var query: String
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            SymbolIcon("magnifyingglass", size: 13, color: GrokColor.sidebarInk)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .grokText(.labelPlain, color: GrokColor.sidebarInk)
                .focused($isFocused)
                .onExitCommand(perform: onDismiss)

            Button(action: onDismiss) {
                SymbolIcon("xmark.circle.fill", size: 13, color: GrokColor.sidebarSubtleInk)
            }
            .buttonStyle(GrokButtonStyle())
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 36)
        .background(Capsule().fill(GrokColor.sidebarSelection))
        .decorativeBorder(GrokColor.sidebarDivider, cornerRadius: 18)
        .contentShape(Capsule())
        // Clicking anywhere on the pill should land the caret in the field.
        .onTapGesture { isFocused = true }
        // Opening search focuses the field rather than leaving the caret in
        // whatever was focused before. The hop lets the field reach the window
        // first, which it must before it can become first responder.
        .onAppear {
            DispatchQueue.main.async { isFocused = true }
        }
    }
}
