//
//  SideBarEmptyState.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// The planet illustration shown when a flow has no history yet.
struct SideBarEmptyState: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(GrokAsset.emptyState)
                .resizable()
                .scaledToFit()
                .frame(height: 120)

            VStack(spacing: 4) {
                Text(title)
                    .grokText(.heading, color: GrokColor.sidebarInk)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .grokText(.micro, color: GrokColor.sidebarSubtleInk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 130)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The frosted upgrade card pinned to the bottom of the sidebar.
struct SideBarUpgradeCard: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("Upgrade your plan to unlock more")
                .grokText(.upgradeTitle, color: GrokColor.sidebarInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: action) {
                Text("Upgrade Now")
                    .grokText(.upgradeAction, color: GrokColor.black1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .hoverBackground(GrokColor.white1, hover: GrokColor.white2, cornerRadius: 10)
            }
            .buttonStyle(GrokButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(
            RoundedRectangle(cornerRadius: GrokMetrics.tileRadius, style: .continuous)
                .fill(Color.white.opacity(0.1))
        )
    }
}
