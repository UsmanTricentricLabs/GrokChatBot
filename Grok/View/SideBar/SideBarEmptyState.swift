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
///
/// The whole card is the target, not just the button inside it: the card has
/// no other purpose, so anywhere on it opening the paywall is what the pointer
/// suggests. The inner label keeps its own background to stay on design, but
/// it is drawn rather than clickable so the two cannot take the click apart.
struct SideBarUpgradeCard: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text("sidebar.upgrade.title".localized)
                    .grokText(.upgradeTitle, color: GrokColor.sidebarInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("sidebar.upgrade.action".localized)
                    .grokText(.upgradeAction, color: GrokColor.black1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isHovering ? GrokColor.white2 : GrokColor.white1)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(
                RoundedRectangle(cornerRadius: GrokMetrics.tileRadius, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.16 : 0.1))
            )
            .contentShape(
                RoundedRectangle(cornerRadius: GrokMetrics.tileRadius, style: .continuous)
            )
        }
        .buttonStyle(GrokButtonStyle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
