import Foundation

/// A 4-digit pairing code shown on the Mac and entered on the phone.
public struct PairingCode: Sendable, Equatable, CustomStringConvertible {
    public let value: String

    /// Fails for anything that is not exactly four decimal digits.
    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 4, trimmed.allSatisfy(\.isNumber) else { return nil }
        self.value = trimmed
    }

    /// Generates a uniformly random 4-digit code (0000–9999).
    public static func random<G: RandomNumberGenerator>(using generator: inout G) -> PairingCode {
        let n = Int.random(in: 0...9999, using: &generator)
        return PairingCode(String(format: "%04d", n))!
    }

    public static func random() -> PairingCode {
        var g = SystemRandomNumberGenerator()
        return random(using: &g)
    }

    public var description: String { value }
}
