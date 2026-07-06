import Foundation
import LocalAuthentication
import Security

/// Stores the terminal master password on the phone behind Face ID / Touch ID,
/// so after the first manual entry the user unlocks the terminal with biometrics
/// instead of retyping the password each time.
///
/// The item is protected by a `SecAccessControl` requiring biometry, in the
/// device-only keychain — reading it triggers the biometric prompt and the
/// secret never syncs to iCloud or leaves the device.
enum TerminalCredentialStore {
    private static let account = "com.fiple.terminal.masterPassword"

    /// Whether a biometric-protected password is stored (does not prompt).
    static func hasStoredPassword() -> Bool {
        var query = baseQuery()
        query[kSecReturnData as String] = false
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // Present-but-locked reports interactionNotAllowed; either means it exists.
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Saves (or replaces) the password behind a biometric access control.
    @discardableResult
    static func save(_ password: String) -> Bool {
        SecItemDelete(baseQuery() as CFDictionary)
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, nil
        ) else { return false }

        var query = baseQuery()
        query[kSecValueData as String] = Data(password.utf8)
        query[kSecAttrAccessControl as String] = access
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Retrieves the password, prompting for Face ID / Touch ID. Returns nil if
    /// the user cancels, biometrics fail, or nothing is stored.
    static func retrieve(reason: String) async -> String? {
        let context = LAContext()
        context.localizedReason = reason

        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecUseAuthenticationContext as String] = context

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var item: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &item)
                guard status == errSecSuccess, let data = item as? Data else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }
        }
    }

    /// Removes the stored password (e.g. on disconnect / unpair).
    static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
