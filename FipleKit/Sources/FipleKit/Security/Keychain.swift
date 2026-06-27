import Foundation
import Security

/// Minimal Keychain wrapper for small secrets (the pairing session token).
///
/// Items are stored as generic passwords scoped to this app, device-only
/// (never synced to iCloud) and readable after first unlock — so a known phone
/// can reconnect after a reboot, but the secret never leaves the device and is
/// not exposed in plaintext via `UserDefaults` or unencrypted backups.
public enum Keychain {
    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
    }

    /// Stores (or replaces) a string value for `key`.
    @discardableResult
    public static func set(_ value: String, for key: String) -> Bool {
        let data = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(baseQuery(for: key) as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var addQuery = baseQuery(for: key)
        addQuery.merge(attributes) { _, new in new }
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    /// Reads the string value for `key`, or `nil` if absent.
    public static func get(_ key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes the value for `key` (no-op if absent).
    public static func remove(_ key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }
}
