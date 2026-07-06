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
    /// proof of the master password. Both factors are required (ADR-0005).
    case auth(token: String, passwordProof: String)
    /// Reattach to an existing session after a reconnect, replaying its buffer.
    case attach(sessionID: String)
    /// Start a fresh shell session (no prior session to resume).
    case newSession
}

extension TerminalClientControl: WireTypeTagged {
    public static let knownTypes: Set<String> = Set(Tag.allCases.map(\.rawValue))
}

extension TerminalClientControl: Codable {
    private enum Tag: String, Codable, CaseIterable { case auth, attach, newSession }
    private enum CodingKeys: String, CodingKey { case type, token, passwordProof, sessionID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Tag.self, forKey: .type) {
        case .auth:
            self = .auth(
                token: try c.decode(String.self, forKey: .token),
                passwordProof: try c.decode(String.self, forKey: .passwordProof)
            )
        case .attach:
            self = .attach(sessionID: try c.decode(String.self, forKey: .sessionID))
        case .newSession:
            self = .newSession
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .auth(token, passwordProof):
            try c.encode(Tag.auth, forKey: .type)
            try c.encode(token, forKey: .token)
            try c.encode(passwordProof, forKey: .passwordProof)
        case let .attach(sessionID):
            try c.encode(Tag.attach, forKey: .type)
            try c.encode(sessionID, forKey: .sessionID)
        case .newSession:
            try c.encode(Tag.newSession, forKey: .type)
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
