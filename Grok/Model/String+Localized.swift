//
//  String+Localized.swift
//  Grok
//
//  Created by Tricentric Labs on 08/10/2026.
//

import Foundation

/// Looks a key up in the language the app is currently running in.
///
/// Copy is written as keys rather than literals because a price, a file name
/// or a trial length has to be dropped into a sentence that other languages
/// order differently.
///
/// The lookup goes through `LocalizationManager` rather than
/// `NSLocalizedString`, because the language is chosen inside the app and the
/// system's own resolution cannot be changed while the app is running.
extension String {

    /// The translation for this key, or the key itself when none is shipped.
    var localized: String {
        LocalizationManager.bundle.localizedString(forKey: self, value: nil, table: nil)
    }

    /// The translation with its placeholders filled in.
    ///
    /// Positional specifiers (`%1$@`) are used wherever a sentence takes more
    /// than one value, so a translation can reorder them without reordering
    /// the call.
    func localized(_ arguments: CVarArg...) -> String {
        String(format: localized, locale: LocalizationManager.bundle.preferredLocale, arguments: arguments)
    }
}

private extension Bundle {

    /// The locale matching this bundle, so numbers inside a formatted string
    /// are grouped the way the chosen language expects.
    var preferredLocale: Locale {
        guard let identifier = preferredLocalizations.first else { return .current }
        return Locale(identifier: identifier)
    }
}
