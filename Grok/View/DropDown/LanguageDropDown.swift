//
//  LanguageDropDown.swift
//  Grok
//
//  Created by Tricentric Labs on 08/10/2026.
//

import SwiftUI

/// The menu behind the Language pill: every language the app ships, with the
/// one in force checked.
///
/// Each row is labelled in its own language, with the English name underneath,
/// so a reader can find their language whether or not they read the script the
/// rest of the app is currently in.
struct LanguageDropDown: View {

    /// Closes the popover once a language has been chosen.
    let onDismiss: () -> Void

    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AppLanguage.menuOrder) { language in
                    LanguageRow(
                        language: language,
                        isSelected: language == localization.language
                    ) {
                        localization.select(language)
                        onDismiss()
                    }
                }
            }
            .padding(8)
        }
        .frame(width: 260)
        // Tall enough for most of the list, short enough to stay a popover
        // rather than a second window.
        .frame(maxHeight: 420)
    }
}

/// One language row: its own name, its English name, and a check when active.
private struct LanguageRow: View {
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(language.endonym)
                        .grokText(.body, color: GrokColor.black1)
                        .lineLimit(1)

                    // Redundant for English, and a row that repeats itself
                    // reads like a mistake.
                    if language.englishName != language.endonym {
                        Text(language.englishName)
                            .grokText(.metadata, color: GrokColor.black6)
                            .lineLimit(1)
                    }
                }
                // The endonym is written in its own script, which is read in
                // its own direction regardless of the app's current one.
                .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)

                Spacer(minLength: 0)

                if isSelected {
                    SymbolIcon("checkmark", size: 13, weight: .semibold, color: GrokColor.black1)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .contentShape(Rectangle())
            .hoverBackground(.clear, hover: GrokColor.white3, cornerRadius: 10)
        }
        .buttonStyle(GrokButtonStyle())
    }
}
