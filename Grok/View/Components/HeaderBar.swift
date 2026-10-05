//
//  HeaderBar.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import SwiftUI

/// The top bar shared by every flow: the model name on the left, Language and
/// Settings on the right, plus a sidebar toggle once the rail is collapsed.
struct HeaderBar: View {
    var showsSidebarToggle: Bool = false
    var onToggleSidebar: () -> Void = {}

    @State private var isSettingsPresented = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsSidebarToggle {
                Button(action: onToggleSidebar) {
                    SymbolIcon("sidebar.leading", size: 18, color: GrokColor.black1)
                        .frame(width: 32, height: 32)
                        .hoverBackground(.clear, hover: GrokColor.white4, cornerRadius: 8)
                }
                .buttonStyle(GrokButtonStyle())
                .help("Show sidebar")
            }

            ModelPicker()

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                StarfieldPill(title: "Language", asset: GrokAsset.language) {}
                StarfieldPill(title: "Settings", asset: GrokAsset.settings) {
                    isSettingsPresented.toggle()
                }
                .popover(isPresented: $isSettingsPresented, arrowEdge: .bottom) {
                    SettingDropDown { isSettingsPresented = false }
                }
            }
        }
        .padding(.trailing, GrokMetrics.contentPadding)
        // With the sidebar collapsed the window's traffic lights sit over this
        // bar, so the leading content starts clear of them.
        .padding(.leading, showsSidebarToggle ? 76 : GrokMetrics.contentPadding)
        .frame(height: GrokMetrics.headerHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(GrokColor.white3)
                .frame(height: 1)
        }
    }
}

/// The model name with its chevron, opening a popover of the available
/// models. A plain button is used rather than `Menu` so the 24pt bold label
/// renders exactly as designed.
struct ModelPicker: View {
    private static let models = ["Grok", "Grok Mini"]

    @State private var selection = "Grok"
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 12) {
                Text(selection)
                    .grokText(.sectionTitle, color: GrokColor.black1)
                    .fixedSize()
                SymbolIcon("chevron.down", size: 15, weight: .medium, color: GrokColor.black1)
            }
            .frame(height: 32)
        }
        .buttonStyle(GrokButtonStyle())
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Self.models, id: \.self) { model in
                    Button {
                        selection = model
                        isPresented = false
                    } label: {
                        HStack(spacing: 10) {
                            Text(model)
                                .grokText(.caption, color: GrokColor.black1)
                            Spacer(minLength: 16)
                            if model == selection {
                                SymbolIcon("checkmark", size: 12, weight: .medium, color: GrokColor.black1)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .hoverBackground(.clear, hover: GrokColor.white3, cornerRadius: 10)
                    }
                    .buttonStyle(GrokButtonStyle())
                }
            }
            .padding(6)
            .frame(width: 180)
        }
    }
}

/// A header pill plated with the same starfield as the sidebar.
struct StarfieldPill: View {
    let title: String
    let asset: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                GrokIcon(asset, size: 16, color: .white)
                Text(title)
                    .grokText(.body, color: .white)
                    .fixedSize()
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(SideBarBackground())
            .clipShape(Capsule())
        }
        .buttonStyle(GrokButtonStyle())
    }
}
