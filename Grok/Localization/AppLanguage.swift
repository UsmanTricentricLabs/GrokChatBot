//
//  AppLanguage.swift
//  Grok
//
//  Created by Tricentric Labs on 08/10/2026.
//

import Foundation

/// A language the app ships strings for.
///
/// The raw value is the `.lproj` folder name, so adding a language is a new
/// case plus a folder of the same name — nothing else has to be told about it.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {

    case english = "en"
    case arabic = "ar"
    case catalan = "ca"
    case chinese = "zh-Hans"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case japanese = "ja"
    case korean = "ko"
    case russian = "ru"
    case spanish = "es"
    case vietnamese = "vi"

    var id: String { rawValue }

    /// The language's name in that language, which is how a language picker
    /// has to read: someone looking for their own language cannot be expected
    /// to recognise its English name.
    var endonym: String {
        switch self {
        case .english: return "English"
        case .arabic: return "العربية"
        case .catalan: return "Català"
        case .chinese: return "简体中文"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .russian: return "Русский"
        case .spanish: return "Español"
        case .vietnamese: return "Tiếng Việt"
        }
    }

    /// The English name, shown under the endonym so the row is readable even
    /// when the script is not one the reader knows.
    var englishName: String {
        switch self {
        case .english: return "English"
        case .arabic: return "Arabic"
        case .catalan: return "Catalan"
        case .chinese: return "Chinese (Simplified)"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .russian: return "Russian"
        case .spanish: return "Spanish"
        case .vietnamese: return "Vietnamese"
        }
    }

    /// Arabic lays out right to left, which flips the whole shell rather than
    /// just the text.
    var isRightToLeft: Bool { self == .arabic }

    /// The locale to hand SwiftUI, so dates, numbers and the App Store's own
    /// price formatting follow the chosen language too.
    var locale: Locale { Locale(identifier: rawValue) }

    /// English first, then alphabetical by English name — the order a picker
    /// of a dozen languages is easiest to scan in.
    static var menuOrder: [AppLanguage] {
        let rest = allCases
            .filter { $0 != .english }
            .sorted { $0.englishName < $1.englishName }

        return [.english] + rest
    }

    /// The shipped language that best matches the system's preferred order,
    /// falling back to English. `Bundle.preferredLocalizations` is not used
    /// here because it answers for the main bundle's own localizations, and
    /// this has to resolve before any bundle is chosen.
    static var systemPreferred: AppLanguage {
        for identifier in Locale.preferredLanguages {
            // "zh-Hans-US" and "fr-CA" both have to find their language.
            if let exact = AppLanguage(rawValue: identifier) { return exact }

            let code = identifier.split(separator: "-").first.map(String.init) ?? identifier

            if code == "zh" { return .chinese }
            if let match = allCases.first(where: { $0.rawValue == code }) { return match }
        }

        return .english
    }
}
