//
//  SettingDropDown.swift
//  Grok
//
//  Created by Tricentric Labs on 05/10/2026.
//

import AppKit
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

    /// Linked from the foot of the paywall. The App Store requires both to be
    /// reachable from anywhere a subscription is sold.
    static let terms = URL(string: "https://tricentriclabs.com/grok/terms")!
    static let privacy = URL(string: "https://tricentriclabs.com/grok/privacy")!
}

/// The menu behind the Settings pill: Share, Rate Us, Help & Support and
/// Restore Purchase, one row each.
struct SettingDropDown: View {
    /// Closes the popover once a row has done its work.
    let onDismiss: () -> Void

    @ObservedObject private var iap = IAPManager.shared

    /// The Share row's own view, which the system picker hangs off.
    @State private var shareAnchor: NSView?
    @State private var isRestoring = false
    @State private var restoreResult: RestoreResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SettingRow(title: "common.share".localized, symbol: "square.and.arrow.up", action: share)
                .background(ViewAnchor(view: $shareAnchor))

            SettingRow(title: "settings.rateUs".localized, symbol: "star") {
                open(SettingsDestination.review)
            }

            SettingRow(title: "settings.help".localized, symbol: "questionmark.circle") {
                open(SettingsDestination.support)
            }

            SettingRow(
                title: "settings.restore".localized,
                symbol: "arrow.clockwise",
                isBusy: isRestoring,
                action: restorePurchases
            )
        }
        .padding(8)
        .frame(width: 260)
        .alert(item: $restoreResult) { result in
            Alert(title: Text(result.title), message: Text(result.detail), dismissButton: .default(Text("common.ok".localized)))
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

    /// Asks `IAPManager` to restore anything bought with this account. The row
    /// stays put while it runs, because the sheet it raises belongs to the
    /// system and the result is worth reporting either way.
    ///
    /// The sync itself is not repeated here: the manager owns it, and it is the
    /// only place that may unlock premium, so a restore started from this menu
    /// updates the rest of the app exactly as one started from the paywall.
    private func restorePurchases() {
        guard !isRestoring else { return }
        isRestoring = true

        iap.restorePurchases { restored in
            isRestoring = false

            if restored {
                restoreResult = .restored
            } else if let reason = iap.errorMessage {
                // Taken from the manager and cleared, so the paywall does not
                // later show a failure that has already been reported here.
                iap.errorMessage = nil
                restoreResult = .failed(reason)
            } else {
                restoreResult = .nothingToRestore
            }
        }
    }

    /// What the alert says once the restore finishes.
    enum RestoreResult: Identifiable {
        case restored
        case nothingToRestore
        case failed(String)

        var id: String { title + detail }

        var title: String {
            switch self {
            case .restored: return "restore.success.title".localized
            case .nothingToRestore: return "restore.none.title".localized
            case .failed: return "restore.failed.title".localized
            }
        }

        var detail: String {
            switch self {
            case .restored:
                return "restore.success.detail".localized
            case .nothingToRestore:
                return "restore.none.detail".localized
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
