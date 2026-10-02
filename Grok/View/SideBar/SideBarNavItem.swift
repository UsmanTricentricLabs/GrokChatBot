//
//  SideBarNavItem.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// A destination row in the sidebar — Create Image and PDF Summary.
struct SideBarNavItem: View {
    let title: String
    let asset: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                GrokIcon(asset, size: 20, color: GrokColor.sidebarInk)
                    .frame(width: 28)
                Text(title)
                    .grokText(.control, color: GrokColor.sidebarInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .hoverBackground(
                isSelected ? GrokColor.sidebarSelection : .clear,
                hover: isSelected ? GrokColor.sidebarSelection : Color.white.opacity(0.1),
                cornerRadius: GrokMetrics.navItemRadius
            )
        }
        .buttonStyle(GrokButtonStyle())
    }
}

/// The white "New Chat" pill that opens the sidebar.
struct SideBarNewChatButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                GrokIcon(GrokAsset.newChat, size: 24, color: GrokColor.black1)
                    .frame(width: 28)
                Text("New Chat")
                    .grokText(.subheading, color: GrokColor.black1)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
            .hoverBackground(GrokColor.white1, hover: GrokColor.white2, cornerRadius: 24)
        }
        .buttonStyle(GrokButtonStyle())
    }
}
