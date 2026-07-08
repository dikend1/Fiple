import Foundation

/// Payload of a `RESIZE` terminal frame: the client's current terminal grid.
/// Sent whenever the on-screen size changes (rotation, keyboard show/hide) so
/// the Mac's pty reflows full-screen apps like vim and htop.
public struct TerminalResize: Codable, Equatable, Sendable {
    public let cols: Int
    public let rows: Int

    public init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
    }
}

/// Why a terminal auth handshake was rejected, so the phone can react distinctly
/// (retry vs. show a lockout) rather than treating every failure the same.
public enum TerminalAuthFailReason: String, Sendable, Equatable, Codable {
    /// The pairing token was missing or unrecognized.
    case badToken
    /// The master-password proof did not verify.
    case badPassword
    /// Too many wrong passwords; auth is temporarily locked out.
    case lockedOut
    /// The service is disabled on the Mac.
    case serviceDisabled
}

/// CONTROL-frame payloads sent from the phone to the Mac's terminal service.
public enum TerminalClientControl: Sendable, Equatable {
    /// Authenticate the terminal session: the tile-channel pairing token plus a
    /// proof of the master password (both factors required, ADR-0005). If
    /// `resumeSessionID` names a shell session still alive on the Mac (within its
    /// grace period), the Mac reattaches to it and replays its buffer; otherwise
    /// a fresh shell is started. Nil on a first connection.
    case auth(token: String, passwordProof: String, resumeSessionID: String?)
    /// The phone closed a session tab: end that shell now instead of letting it
    /// idle through the reattach grace period. Only honoured on an authenticated
    /// connection. An older Mac skips this unknown type — the shell then simply
    /// dies at grace expiry (soft degradation).
    case endSession(sessionID: String)
}

extension TerminalClientControl: WireTypeTagged {
    public static let knownTypes: Set<String> = Set(Tag.allCases.map(\.rawValue))
}

extension TerminalClientControl: Codable {
    private enum Tag: String, Codable, CaseIterable { case auth, endSession }
    private enum CodingKeys: String, CodingKey { case type, token, passwordProof, resumeSessionID, sessionID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Tag.self, forKey: .type) {
        case .auth:
            self = .auth(
                token: try c.decode(String.self, forKey: .token),
                passwordProof: try c.decode(String.self, forKey: .passwordProof),
                resumeSessionID: try c.decodeIfPresent(String.self, forKey: .resumeSessionID)
            )
        case .endSession:
            self = .endSession(sessionID: try c.decode(String.self, forKey: .sessionID))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .auth(token, passwordProof, resumeSessionID):
            try c.encode(Tag.auth, forKey: .type)
            try c.encode(token, forKey: .token)
            try c.encode(passwordProof, forKey: .passwordProof)
            try c.encodeIfPresent(resumeSessionID, forKey: .resumeSessionID)
        case let .endSession(sessionID):
            try c.encode(Tag.endSession, forKey: .type)
            try c.encode(sessionID, forKey: .sessionID)
        }
    }
}

/// CONTROL-frame payloads sent from the Mac's terminal service to the phone.
public enum TerminalServerControl: Sendable, Equatable {
    /// Auth succeeded; the shell session id the phone reattaches to later.
    case authOK(sessionID: String)
    /// Auth rejected, with a typed reason.
    case authFailed(reason: TerminalAuthFailReason)
    /// The shell exited; carries its exit code when known.
    case sessionEnded(exitCode: Int32?)
}

extension TerminalServerControl: WireTypeTagged {
    public static let knownTypes: Set<String> = Set(Tag.allCases.map(\.rawValue))
}

extension TerminalServerControl: Codable {
    private enum Tag: String, Codable, CaseIterable { case authOK, authFailed, sessionEnded }
    private enum CodingKeys: String, CodingKey { case type, sessionID, reason, exitCode }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Tag.self, forKey: .type) {
        case .authOK:
            self = .authOK(sessionID: try c.decode(String.self, forKey: .sessionID))
        case .authFailed:
            // Tolerate an unknown reason from a newer peer rather than failing.
            let raw = try c.decode(String.self, forKey: .reason)
            self = .authFailed(reason: TerminalAuthFailReason(rawValue: raw) ?? .badPassword)
        case .sessionEnded:
            self = .sessionEnded(exitCode: try c.decodeIfPresent(Int32.self, forKey: .exitCode))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .authOK(sessionID):
            try c.encode(Tag.authOK, forKey: .type)
            try c.encode(sessionID, forKey: .sessionID)
        case let .authFailed(reason):
            try c.encode(Tag.authFailed, forKey: .type)
            try c.encode(reason.rawValue, forKey: .reason)
        case let .sessionEnded(exitCode):
            try c.encode(Tag.sessionEnded, forKey: .type)
            try c.encodeIfPresent(exitCode, forKey: .exitCode)
        }
    }
}
