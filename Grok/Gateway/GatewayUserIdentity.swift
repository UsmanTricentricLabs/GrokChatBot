//
//  GatewayUserIdentity.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import Foundation
import Security

/// The anonymous installation identifier sent as `X-User-Id`.
///
/// It is a random UUID generated once and kept for as long as the app is
/// installed. It deliberately carries nothing that identifies a person: no
/// email, Apple ID, device serial or account of any kind — the app has no
/// sign-in at all.
///
/// It is held in the data protection Keychain, the one an app owns outright.
/// The older file-based Keychain is deliberately not used: items there belong
/// to the login keychain and are guarded by an access list, which makes macOS
/// ask for the login password whenever the app's signature changes — a prompt
/// the customer would see in the middle of sending a prompt, for a value that
/// is not a secret. Should even that be unavailable, the identifier falls back
/// to `UserDefaults`, because an installation id is worth nothing to anyone
/// who could read it.
enum GatewayUserIdentity {

    private nonisolated static let service = "com.grok.ai.app.gateway"
    private nonisolated static let account = "anonymous-user-id"
    /// Where the identifier lands when the Keychain refuses it.
    private nonisolated static let defaultsKey = "gateway.anonymousUserId"

    /// Cached so repeated requests do not hit the Keychain on every call.
    private nonisolated static let lock = NSLock()
    nonisolated(unsafe) private static var storedValue: String?

    /// The lowercased UUID for this installation, creating it on first use.
    nonisolated static var current: String {
        lock.lock()
        defer { lock.unlock() }

        if let storedValue { return storedValue }

        let identifier = read() ?? create()
        storedValue = identifier
        return identifier
    }

    // MARK: Keychain

    /// The query both reads and writes share. `kSecUseDataProtectionKeychain`
    /// is what keeps this out of the login keychain, and so out of the
    /// password prompt.
    private nonisolated static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    private nonisolated static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            return value
        }

        // Nothing in the Keychain: either this is a first run, or a previous
        // one had to fall back.
        let fallback = UserDefaults.standard.string(forKey: defaultsKey)
        return (fallback?.isEmpty == false) ? fallback : nil
    }

    private nonisolated static func create() -> String {
        let identifier = UUID().uuidString.lowercased()
        guard let data = identifier.data(using: .utf8) else { return identifier }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        // The identifier is only needed while the app is running, and never
        // needs to leave this device.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemDelete(attributes as CFDictionary)
        let status = SecItemAdd(attributes as CFDictionary, nil)

        if status != errSecSuccess {
            UserDefaults.standard.set(identifier, forKey: defaultsKey)
        }

        return identifier
    }
}
