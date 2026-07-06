import Foundation

/// Decides whether a terminal auth handshake is allowed, combining the two
/// factors ADR-0005 requires — the tile-channel pairing token and the master
/// password — behind the same brute-force lockout used for pairing.
///
/// Value type with an injectable clock so the lockout window is testable. Own it
/// from the single actor that runs the terminal listener.
public struct TerminalAuthenticator: Sendable {
    /// Reuses the pairing brute-force guard rather than forking a second one, so
    /// password guessing locks out on the same policy as code guessing.
    public private(set) var throttle: PairingThrottle
    private let record: MasterPasswordRecord
    private let authorizedTokens: Set<String>

    public init(
        record: MasterPasswordRecord,
        authorizedTokens: Set<String>,
        throttle: PairingThrottle = PairingThrottle()
    ) {
        self.record = record
        self.authorizedTokens = authorizedTokens
        self.throttle = throttle
    }

    public enum Decision: Sendable, Equatable {
        case authorized(TerminalServerControl) // .authOK(sessionID:)
        case rejected(TerminalAuthFailReason)
    }

    /// Judges one `auth` control message. `makeSessionID` supplies the id for a
    /// freshly authorized session (injected so it stays deterministic in tests).
    public mutating func authenticate(
        token: String,
        passwordProof: String,
        now: Date,
        makeSessionID: () -> String
    ) -> Decision {
        // A standing lockout rejects before any credential is examined, and
        // without consuming an attempt.
        if throttle.isLockedOut(now: now) {
            return .rejected(.lockedOut)
        }

        // The token is a high-entropy bearer credential already issued by the
        // tile channel; a mismatch is a protocol error, not a guess, so it does
        // not consume a password attempt.
        guard authorizedTokens.contains(token) else {
            return .rejected(.badToken)
        }

        let matches = MasterPassword.verify(passwordProof, against: record)
        switch throttle.register(matches: matches, now: now) {
        case .accepted:
            return .authorized(.authOK(sessionID: makeSessionID()))
        case .rejected, .lockedOut:
            // Both map to a password failure for the client; the throttle has
            // recorded the attempt and will lock out on its own policy.
            return .rejected(throttle.isLockedOut(now: now) ? .lockedOut : .badPassword)
        case .ignored:
            return .rejected(.lockedOut)
        }
    }
}
