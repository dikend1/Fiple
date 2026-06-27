import Foundation

/// Brute-force guard for the 4-digit pairing code.
///
/// Connection-agnostic on purpose: one instance tracks attempts across *every*
/// socket in a pairing session, so an attacker can't reset the count by opening
/// a fresh connection per guess. State is cleared only on a successful pair or
/// an explicit restart of advertising — **never** when a socket drops. After
/// `maxAttempts` wrong guesses it locks out for `lockoutDuration`; the caller is
/// expected to rotate the code on lockout so any guessed digits are worthless.
public struct PairingThrottle: Sendable, Equatable {
    public let maxAttempts: Int
    public let lockoutDuration: TimeInterval

    public private(set) var failedAttempts: Int = 0
    public private(set) var lockedOutUntil: Date?

    public init(maxAttempts: Int = 5, lockoutDuration: TimeInterval = 30) {
        precondition(maxAttempts >= 1)
        self.maxAttempts = maxAttempts
        self.lockoutDuration = lockoutDuration
    }

    public enum Outcome: Sendable, Equatable {
        /// Code matched; accept the pairing.
        case accepted
        /// Wrong code; `remaining` guesses left before lockout.
        case rejected(remaining: Int)
        /// This guess hit the limit: rotate the code, tell the peer, drop the
        /// socket. Lockout is now in effect.
        case lockedOut
        /// Already locked out; reject without consuming an attempt.
        case ignored
    }

    /// Records one pairing attempt. `matches` is whether the supplied code
    /// equalled the current code; `now` is injected so the lockout window is
    /// testable.
    public mutating func register(matches: Bool, now: Date) -> Outcome {
        // A lapsed lockout clears itself before this attempt is judged.
        if let until = lockedOutUntil, now >= until {
            lockedOutUntil = nil
            failedAttempts = 0
        }
        if let until = lockedOutUntil, now < until { return .ignored }

        if matches {
            reset()
            return .accepted
        }

        failedAttempts += 1
        if failedAttempts >= maxAttempts {
            lockedOutUntil = now.addingTimeInterval(lockoutDuration)
            return .lockedOut
        }
        return .rejected(remaining: maxAttempts - failedAttempts)
    }

    /// Whether pairing is currently locked out.
    public func isLockedOut(now: Date) -> Bool {
        guard let until = lockedOutUntil else { return false }
        return now < until
    }

    /// Clears all attempt state. Call only on a successful pair or an explicit
    /// restart of advertising — not on socket close.
    public mutating func reset() {
        failedAttempts = 0
        lockedOutUntil = nil
    }
}
