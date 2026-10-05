//
//  SettingDropDown.swift
//  Grok
//
//  Created by Tricentric Labs on 05/10/2026.
//

import AppKit
import StoreKit
import SwiftUI

/// Where the Settings menu's links point. One place to edit once the listing
/// and the support address are live.
nonisolated enum SettingsDestination {
    /// The App Store listing's numeric id.
    static let appStoreID = "0000000000"

    /// The link that travels when the app is shared.
    static var listing: URL { URL(string: "https://apps.apple.com/app/id\(appStoreID)")! }

    /// Opens the listing straight on its review sheet.
    static var review: URL {
        URL(string: "macappstore://apps.apple.com/app/id\(appStoreID)?action=write-review")!
    }

    static let support = URL(string: "mailto:support@tricentriclabs.com")!
}

/// The menu behind the Settings pill: Share, Rate Us, Help & Support and
/// Restore Purchase, one row each.
struct SettingDropDown: View {
    /// Closes the popover once a row has done its work.
    let onDismiss: () -> Void

    /// The Share row's own view, which the system picker hangs off.
    @State private var shareAnchor: NSView?
    @State private var isRestoring = false
    @State private var restoreResult: RestoreResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SettingRow(title: "Share", symbol: "square.and.arrow.up", action: share)
                .background(ViewAnchor(view: $shareAnchor))

            SettingRow(title: "Rate Us", symbol: "star") {
                open(SettingsDestination.review)
            }

            SettingRow(title: "Help & Support", symbol: "questionmark.circle") {
                open(SettingsDestination.support)
            }

            SettingRow(
                title: "Restore Purchase",
                symbol: "arrow.clockwise",
                isBusy: isRestoring,
                action: restorePurchases
            )
        }
        .padding(8)
        .frame(width: 260)
        .alert(item: $restoreResult) { result in
            Alert(title: Text(result.title), message: Text(result.detail), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: Actions

    private func share() {
        // The picker needs a view still on screen to point at, so the popover
        // closes only after it has taken over the anchor.
        guard let shareAnchor, shareAnchor.window != nil else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(SettingsDestination.listing.absoluteString, forType: .string)
            onDismiss()
            return
        }
        NSSharingServicePicker(items: [SettingsDestination.listing]).show(
            relativeTo: .zero,
            of: shareAnchor,
            preferredEdge: .maxX
        )
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
        onDismiss()
    }

    /// Asks the App Store to restore anything bought with this account. The
    /// row stays put while it runs, because the sheet it raises belongs to the
    /// system and the result is worth reporting either way.
    private func restorePurchases() {
        guard !isRestoring else { return }
        isRestoring = true

        Task {
            do {
                try await AppStore.sync()
                restoreResult = .restored
            } catch {
                restoreResult = .failed(error.localizedDescription)
            }
            isRestoring = false
        }
    }

    /// What the alert says once the restore finishes.
    enum RestoreResult: Identifiable {
        case restored
        case failed(String)

        var id: String { title + detail }

        var title: String {
            switch self {
            case .restored: return "Purchases Restored"
            case .failed: return "Restore Failed"
            }
        }

        var detail: String {
            switch self {
            case .restored:
                return "Anything bought with this Apple Account is available again."
            case .failed(let reason):
                return reason
            }
        }
    }
}

/// One menu row: an outline glyph, a label, and the whole width as its target.
private struct SettingRow: View {
    let title: String
    let symbol: String
    var isBusy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                SymbolIcon(symbol, size: 18, color: GrokColor.black1)
                    .frame(width: 22)
                Text(title)
                    .grokText(.body, color: GrokColor.black1)
                    .fixedSize()
                Spacer(minLength: 0)
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .contentShape(Rectangle())
            .hoverBackground(.clear, hover: GrokColor.white3, cornerRadius: 10)
        }
        .buttonStyle(GrokButtonStyle())
        .disabled(isBusy)
    }
}
