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
/// It is a random UUID generated once and kept in the Keychain, so it survives
/// relaunches and app updates. It deliberately carries nothing that identifies
/// a person: no email, Apple ID, device serial or account of any kind — the
/// app has no sign-in at all.
enum GatewayUserIdentity {

    private nonisolated static let service = "com.grok.ai.app.gateway"
    private nonisolated static let account = "anonymous-user-id"

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

    private nonisolated static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }

        return value
    }

    private nonisolated static func create() -> String {
        let identifier = UUID().uuidString.lowercased()
        guard let data = identifier.data(using: .utf8) else { return identifier }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // The identifier is only needed while the app is running, and never
            // needs to leave this device.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemDelete(attributes as CFDictionary)
        SecItemAdd(attributes as CFDictionary, nil)
        return identifier
    }
}
