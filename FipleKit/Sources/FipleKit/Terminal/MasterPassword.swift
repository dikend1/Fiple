import Foundation
import CommonCrypto

/// A stored master-password verifier for the terminal channel.
///
/// The Mac never stores or transmits the password itself — only a salted
/// PBKDF2-HMAC-SHA256 hash. A phone proves knowledge of the password during the
/// auth handshake; the Mac recomputes the hash and compares. Terminal access is
/// full shell control, so this second factor stands even if the pairing token
/// leaks.
public struct MasterPasswordRecord: Codable, Equatable, Sendable {
    public let salt: Data
    public let hash: Data
    public let iterations: Int

    public init(salt: Data, hash: Data, iterations: Int) {
        self.salt = salt
        self.hash = hash
        self.iterations = iterations
    }
}

public enum MasterPassword {
    /// PBKDF2 iteration count. High enough to make offline guessing slow;
    /// verification cost on a modern Mac is a few milliseconds.
    public static let defaultIterations = 210_000
    private static let saltLength = 16
    private static let keyLength = 32 // SHA-256 output

    /// Derives a fresh verifier for a new or changed password. Each call uses a
    /// new random salt, so two records for the same password never match.
    public static func make(_ password: String, iterations: Int = defaultIterations) -> MasterPasswordRecord {
        var salt = Data(count: saltLength)
        var rng = SystemRandomNumberGenerator()
        for i in 0..<saltLength { salt[i] = UInt8.random(in: .min ... .max, using: &rng) }
        let hash = derive(password: password, salt: salt, iterations: iterations)
        return MasterPasswordRecord(salt: salt, hash: hash, iterations: iterations)
    }

    /// Recomputes the hash for `password` under the record's salt/iterations and
    /// compares in constant time.
    public static func verify(_ password: String, against record: MasterPasswordRecord) -> Bool {
        let candidate = derive(password: password, salt: record.salt, iterations: record.iterations)
        return constantTimeEquals(candidate, record.hash)
    }

    private static func derive(password: String, salt: Data, iterations: Int) -> Data {
        let passwordBytes = Array(password.utf8)
        var derived = Data(count: keyLength)
        let status = derived.withUnsafeMutableBytes { derivedPtr in
            salt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes, passwordBytes.count,
                    saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPBKDFAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    derivedPtr.bindMemory(to: UInt8.self).baseAddress, keyLength
                )
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 derivation failed")
        return derived
    }

    /// Length-independent equality to avoid leaking the hash via timing.
    private static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}
