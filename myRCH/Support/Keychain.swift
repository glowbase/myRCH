import Foundation
import Security

/// Minimal Keychain wrapper for storing the portal credentials securely.
/// Credentials never touch UserDefaults or logs — only the system Keychain,
/// and are only ever sent to RCH's own host over HTTPS.
nonisolated enum Keychain {
    private static let service = "au.org.rch.myrchportal.credentials"

    static func save(username: String, password: String) {
        set("username", username)
        set("password", password)
    }

    static func loadCredentials() -> (username: String, password: String)? {
        guard let username = get("username"), let password = get("password") else { return nil }
        return (username, password)
    }

    static func clear() {
        delete("username")
        delete("password")
    }

    /// The portal-issued web device ID ("remember this device"). Kept across
    /// sign-outs, like a browser's localStorage, so two-factor isn't re-prompted.
    static var deviceID: String? {
        get { get("deviceID") }
        set {
            if let newValue { set("deviceID", newValue) } else { delete("deviceID") }
        }
    }

    // MARK: - Primitive operations

    private static func set(_ account: String, _ value: String) {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
