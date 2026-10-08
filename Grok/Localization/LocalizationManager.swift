//
//  LocalizationManager.swift
//  Grok
//
//  Created by Tricentric Labs on 08/10/2026.
//

import SwiftUI
internal import Combine

/// The app's language, chosen in the app rather than in System Settings.
///
/// macOS resolves `NSLocalizedString` against the system's language list and
/// will not change it while the app runs, so every lookup goes through the
/// `.lproj` bundle held here instead. Changing the language swaps that bundle
/// and republishes, and the shell rebuilds itself against the new one.
@MainActor
final class LocalizationManager: ObservableObject {

    static let shared = LocalizationManager()

    /// The language in force. Published so the shell can rebuild on a change.
    @Published private(set) var language: AppLanguage

    /// Where `String.localized` reads from.
    ///
    /// Static and unisolated because strings are resolved from model and error
    /// types that are not tied to the main actor, and an actor hop is not
    /// available to a plain property read. It is only ever written from
    /// `select(_:)`, on the main actor, which is the one place the language
    /// can change.
    nonisolated(unsafe) private(set) static var bundle: Bundle = .main

    private static let storageKey = "appLanguage"

    private init() {
        let stored = UserDefaults.standard
            .string(forKey: Self.storageKey)
            .flatMap(AppLanguage.init(rawValue:))

        // No stored choice means the app has not been asked yet, so it follows
        // the system until someone says otherwise.
        let resolved = stored ?? .systemPreferred

        language = resolved
        Self.bundle = Self.resolveBundle(for: resolved)
    }

    /// Switches the app's language and remembers it.
    func select(_ language: AppLanguage) {
        guard language != self.language else { return }

        // The bundle is swapped before the published change, so that anything
        // rebuilding in response already reads the new strings.
        Self.bundle = Self.resolveBundle(for: language)
        UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        self.language = language
    }

    /// The `.lproj` bundle for a language, or the main bundle if that language
    /// somehow did not ship — a missing translation must not take the app down.
    private static func resolveBundle(for language: AppLanguage) -> Bundle {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }

        return bundle
    }
}

extension View {

    /// Applies the chosen language to a view tree: its strings, its locale and,
    /// for Arabic, its direction.
    ///
    /// The `id` is what forces the rebuild. SwiftUI has no reason to re-render
    /// on a language change — the strings are read inside `body`, not stored in
    /// state — so the tree is given a new identity and built again.
    func localized(by manager: LocalizationManager) -> some View {
        environment(\.locale, manager.language.locale)
            .environment(\.layoutDirection, manager.language.isRightToLeft ? .rightToLeft : .leftToRight)
            .id(manager.language)
    }
}
