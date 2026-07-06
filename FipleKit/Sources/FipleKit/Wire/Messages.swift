import Foundation

/// Messages sent from the iPhone remote to the Mac companion.
public enum ClientMessage: Sendable, Equatable {
    /// Attempt to pair using the code shown on the Mac (first-time pairing).
    case pair(code: String)
    /// Silently re-authenticate a remembered pairing (no code needed) using the
    /// session token issued at first pair. See PRD `fiple-pairing`.
    case reconnect(token: String)
    /// Trigger a tile by id.
    case run(tileID: UUID)
    /// Trigger a single Fiple Bar action by id. The client sends only the id;
    /// the Mac resolves it against its own saved Fiple Bar / tiles and runs it
    /// only if it exists — so a client can never have the Mac execute an
    /// arbitrary, client-supplied action.
    case runAction(actionID: UUID)
}

extension ClientMessage: WireTypeTagged {
    /// Message types this build understands. A peer running a newer protocol
    /// may send types outside this set; they are skipped, not treated as fatal.
    public static let knownTypes: Set<String> = Set(Tag.allCases.map(\.rawValue))
}

extension ClientMessage: Codable {
    private enum Tag: String, Codable, CaseIterable { case pair, reconnect, run, runAction }
    private enum CodingKeys: String, CodingKey { case type, code, token, tileID, actionID, version }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Tag.self, forKey: .type) {
        case .pair: self = .pair(code: try c.decode(String.self, forKey: .code))
        case .reconnect: self = .reconnect(token: try c.decode(String.self, forKey: .token))
        case .run: self = .run(tileID: try c.decode(UUID.self, forKey: .tileID))
        case .runAction: self = .runAction(actionID: try c.decode(UUID.self, forKey: .actionID))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .pair(code):
            try c.encode(Tag.pair, forKey: .type)
            try c.encode(code, forKey: .code)
            try c.encode(FipleService.protocolVersion, forKey: .version)
        case let .reconnect(token):
            try c.encode(Tag.reconnect, forKey: .type)
            try c.encode(token, forKey: .token)
            try c.encode(FipleService.protocolVersion, forKey: .version)
        case let .run(tileID):
            try c.encode(Tag.run, forKey: .type)
            try c.encode(tileID, forKey: .tileID)
        case let .runAction(actionID):
            try c.encode(Tag.runAction, forKey: .type)
            try c.encode(actionID, forKey: .actionID)
        }
    }
}

/// Why a pairing or reconnect attempt was rejected, so the remote can react
/// distinctly (e.g. surface a lockout) rather than treating every rejection as
/// a wrong code.
public enum PairRejectReason: String, Sendable, Equatable, Codable {
    /// Wrong 4-digit code.
    case incorrectCode
    /// Too many wrong codes; pairing is temporarily locked and the code rotated.
    case tooManyAttempts
    /// A remembered reconnect token no longer matches (pairing was cleared).
    case pairingExpired
}

/// Messages sent from the Mac companion to the iPhone remote.
public enum ServerMessage: Sendable, Equatable {
    /// Pairing succeeded; identifies the Mac and returns the session token the
    /// phone stores to reconnect later without re-entering the code.
    case paired(macID: String, macName: String, token: String)
    /// The Mac's hardware family, sent right after `paired` (on every connect)
    /// so the remote can show the right device icon. A separate message rather
    /// than a field on `paired` so older peers simply skip it.
    case deviceInfo(macKind: MacKind)
    /// Pairing rejected, with a typed reason.
    case pairRejected(reason: PairRejectReason)
    /// The current tile list (sent on connect and whenever tiles change).
    case tilesSnapshot(tiles: [Tile])
    /// The current Fiple Bar (curated quick actions; sent on connect and whenever
    /// the bar changes). Icons are resolved on the Mac and carried here.
    case fipleBar(actions: [Action])
    /// Per-action result of a triggered tile.
    case runResult(RunResult)
    /// Advertises the privileged terminal service on this Mac: whether it is
    /// enabled and, if so, the TCP port its TLS-PSK listener is bound to. Sent
    /// on connect and whenever the Mac toggles the feature. The phone connects
    /// to `port` on the Mac's resolved address, deriving the channel PSK from the
    /// same pairing token (ADR-0005). Older remotes skip this unknown type.
    case terminalService(enabled: Bool, port: UInt16)
}

extension ServerMessage: WireTypeTagged {
    /// Message types this build understands (see ``ClientMessage/knownTypes``).
    public static let knownTypes: Set<String> = Set(Tag.allCases.map(\.rawValue))
}

extension ServerMessage: Codable {
    private enum Tag: String, Codable, CaseIterable { case paired, deviceInfo, pairRejected, tilesSnapshot, fipleBar, runResult, terminalService }
    private enum CodingKeys: String, CodingKey {
        case type, macID, macName, macKind, token, reason, tiles, actions, result, version, enabled, terminalPort
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Tag.self, forKey: .type) {
        case .paired:
            self = .paired(
                macID: try c.decode(String.self, forKey: .macID),
                macName: try c.decode(String.self, forKey: .macName),
                token: try c.decode(String.self, forKey: .token)
            )
        case .deviceInfo:
            // Tolerate an unknown family from a newer peer rather than failing
            // to decode; fall back to the app's original laptop assumption.
            let raw = try c.decode(String.self, forKey: .macKind)
            self = .deviceInfo(macKind: MacKind(rawValue: raw) ?? .laptop)
        case .pairRejected:
            // Tolerate an unknown reason from a newer peer rather than failing
            // to decode the whole message.
            let raw = try c.decode(String.self, forKey: .reason)
            self = .pairRejected(reason: PairRejectReason(rawValue: raw) ?? .incorrectCode)
        case .tilesSnapshot:
            self = .tilesSnapshot(tiles: try c.decode([Tile].self, forKey: .tiles))
        case .fipleBar:
            self = .fipleBar(actions: try c.decode([Action].self, forKey: .actions))
        case .runResult:
            self = .runResult(try c.decode(RunResult.self, forKey: .result))
        case .terminalService:
            self = .terminalService(
                enabled: try c.decode(Bool.self, forKey: .enabled),
                port: try c.decode(UInt16.self, forKey: .terminalPort)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .paired(macID, macName, token):
            try c.encode(Tag.paired, forKey: .type)
            try c.encode(macID, forKey: .macID)
            try c.encode(macName, forKey: .macName)
            try c.encode(token, forKey: .token)
            try c.encode(FipleService.protocolVersion, forKey: .version)
        case let .deviceInfo(macKind):
            try c.encode(Tag.deviceInfo, forKey: .type)
            try c.encode(macKind.rawValue, forKey: .macKind)
        case let .pairRejected(reason):
            try c.encode(Tag.pairRejected, forKey: .type)
            try c.encode(reason.rawValue, forKey: .reason)
        case let .tilesSnapshot(tiles):
            try c.encode(Tag.tilesSnapshot, forKey: .type)
            try c.encode(tiles, forKey: .tiles)
        case let .fipleBar(actions):
            try c.encode(Tag.fipleBar, forKey: .type)
            try c.encode(actions, forKey: .actions)
        case let .runResult(result):
            try c.encode(Tag.runResult, forKey: .type)
            try c.encode(result, forKey: .result)
        case let .terminalService(enabled, port):
            try c.encode(Tag.terminalService, forKey: .type)
            try c.encode(enabled, forKey: .enabled)
            try c.encode(port, forKey: .terminalPort)
        }
    }
}
