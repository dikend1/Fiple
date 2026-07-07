import Foundation
import LocalAuthentication
import Security

/// Remembers the terminal master password on the phone so it's typed once, then
/// unlocked with Face ID / Touch ID on later opens.
///
/// Storage and authentication are separated on purpose. The password lives in
/// the device-only keychain (encrypted, never synced) as a plain item — reliable
/// to write across devices and simulators. Face ID is enforced *separately* via
/// `LAContext` at open time, with passcode fallback, so a biometric hiccup can't
/// leave the password unsaved (which caused re-typing on every open).
enum TerminalCredentialStore {
    private static let account = "com.fiple.terminal.masterPassword"

    /// Whether a password is remembered. Does not prompt.
    static func hasStoredPassword() -> Bool {
        var query = baseQuery()
        query[kSecReturnData as String] = false
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Saves (or replaces) the password. Returns whether it persisted.
    @discardableResult
    static func save(_ password: String) -> Bool {
        SecItemDelete(baseQuery() as CFDictionary)
        var query = baseQuery()
        query[kSecValueData as String] = Data(password.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { return false }
        return hasStoredPassword()
    }

    /// Authenticates with Face ID / Touch ID (passcode fallback), then returns
    /// the remembered password. Returns nil if the user cancels/fails auth, or
    /// nothing is stored. On a device with no passcode set, returns the password
    /// without a prompt (best effort — nothing to authenticate against).
    static func retrieve(reason: String) async -> String? {
        guard hasStoredPassword() else { return nil }

        let context = LAContext()
        var policyError: NSError?
        // deviceOwnerAuthentication = biometrics OR passcode, so a failed Face ID
        // isn't a dead end.
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) {
            let passed = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
                    cont.resume(returning: ok)
                }
            }
            guard passed else { return nil }
        }
        return readPassword()
    }

    /// Forgets the remembered password (e.g. on a wrong-password failure).
    static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func readPassword() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
