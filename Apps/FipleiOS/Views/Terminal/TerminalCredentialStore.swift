import FipleKit
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
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status != errSecSuccess {
            FipleLog.execution.info("terminal credential: none stored (status \(status))")
        }
        return status == errSecSuccess
    }

    /// Saves (or replaces) the password. Returns whether it persisted.
    @discardableResult
    static func save(_ password: String) -> Bool {
        // Purge EVERY stored variant first — synchronizable and not — so a stale
        // item (e.g. one an older build synced to iCloud Keychain) can't be the
        // one a later read returns. The base query matched only non-sync items,
        // which is exactly how a wrong-but-present password survived a "save".
        clearAllVariants()

        var query = baseQuery()
        query[kSecValueData as String] = Data(password.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecAttrSynchronizable as String] = false
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            FipleLog.execution.error("terminal credential: SAVE FAILED — add status \(addStatus)")
            return false
        }
        // Verify by CONTENT, not mere presence: re-read and compare bytes, so
        // this can never again report success while a different value is stored.
        let readBack = readPassword()
        let ok = readBack == password
        FipleLog.execution.info("terminal credential: saved len \(password.count), read-back \(ok ? "matches" : "MISMATCH len \(readBack?.count ?? -1)")")
        return ok
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
            guard passed else {
                FipleLog.execution.info("terminal credential: biometric auth declined/failed")
                return nil
            }
        } else {
            FipleLog.execution.info("terminal credential: no auth policy available (\(policyError?.localizedDescription ?? "?")) — returning without prompt")
        }
        let password = readPassword()
        if password == nil {
            FipleLog.execution.error("terminal credential: auth passed but READ FAILED")
        }
        return password
    }

    /// Forgets the remembered password (e.g. on a wrong-password failure).
    static func clear() {
        FipleLog.execution.notice("terminal credential: CLEARED (wrong-password path)")
        clearAllVariants()
    }

    /// Deletes the item in both synchronizable states, so nothing lingers to be
    /// read back later. `kSecAttrSynchronizableAny` matches sync + non-sync.
    private static func clearAllVariants() {
        var query = baseQuery()
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(query as CFDictionary)
    }

    private static func readPassword() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        // Match either sync state — but there should only ever be the one
        // non-sync item `save` writes now.
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            FipleLog.execution.info("terminal credential: read returned status \(status)")
            return nil
        }
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
