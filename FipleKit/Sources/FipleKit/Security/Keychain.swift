import Foundation
import Security

/// Minimal Keychain wrapper for small secrets (the pairing session token).
///
/// Items are stored as generic passwords scoped to this app, device-only
/// (never synced to iCloud) and readable after first unlock — so a known phone
/// can reconnect after a reboot, but the secret never leaves the device and is
/// not exposed in plaintext via `UserDefaults` or unencrypted backups.
///
/// We use the *data-protection keychain* (the same one iOS uses) rather than the
/// legacy file-based "login" keychain. Access is then governed by the app's
/// keychain-access-group entitlement instead of an ACL keyed to the code
/// signature, so macOS never shows the "Fiple wants to use your confidential
/// information… Always Allow" prompt. The legacy ACL re-prompted on every launch
/// whenever the signature changed (rebuilds, bundle-id changes), since "Always
/// Allow" only sticks for an identical signature.
public enum Keychain {
    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// Query against the legacy (file-based) keychain — only used to migrate a
    /// pre-existing item into the data-protection keychain on first read.
    private static func legacyBaseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: false,
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
    ///
    /// Reads **only** the data-protection keychain. We deliberately do not fall
    /// back to (or migrate from) the legacy keychain: reading a legacy item
    /// decrypts its secret, which is exactly what triggers the "enter the login
    /// keychain password" prompt we are trying to eliminate. A stale legacy token
    /// is instead blind-deleted by `purgeLegacy(_:)` — re-pairing once recreates
    /// the token in the data-protection keychain, after which no prompt appears.
    public static func get(_ key: String) -> String? {
        read(baseQuery(for: key))
    }

    /// Removes any leftover item for `key` from the legacy keychain without
    /// reading it. Deletion does not decrypt the secret, so it never prompts.
    /// Call this once at startup to clean up tokens created by older builds.
    public static func purgeLegacy(_ key: String) {
        SecItemDelete(legacyBaseQuery(for: key) as CFDictionary)
    }

    private static func read(_ base: [String: Any]) -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes the value for `key` (no-op if absent), from both keychains.
    public static func remove(_ key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
        SecItemDelete(legacyBaseQuery(for: key) as CFDictionary)
    }
}
