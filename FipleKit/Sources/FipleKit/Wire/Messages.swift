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
    /// Trigger a single Fiple Bar action (app / website / file).
    case runAction(Action)
}

extension ClientMessage: Codable {
    private enum Tag: String, Codable { case pair, reconnect, run, runAction }
    private enum CodingKeys: String, CodingKey { case type, code, token, tileID, action }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Tag.self, forKey: .type) {
        case .pair: self = .pair(code: try c.decode(String.self, forKey: .code))
        case .reconnect: self = .reconnect(token: try c.decode(String.self, forKey: .token))
        case .run: self = .run(tileID: try c.decode(UUID.self, forKey: .tileID))
        case .runAction: self = .runAction(try c.decode(Action.self, forKey: .action))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .pair(code):
            try c.encode(Tag.pair, forKey: .type)
            try c.encode(code, forKey: .code)
        case let .reconnect(token):
            try c.encode(Tag.reconnect, forKey: .type)
            try c.encode(token, forKey: .token)
        case let .run(tileID):
            try c.encode(Tag.run, forKey: .type)
            try c.encode(tileID, forKey: .tileID)
        case let .runAction(action):
            try c.encode(Tag.runAction, forKey: .type)
            try c.encode(action, forKey: .action)
        }
    }
}

/// Messages sent from the Mac companion to the iPhone remote.
public enum ServerMessage: Sendable, Equatable {
    /// Pairing succeeded; identifies the Mac and returns the session token the
    /// phone stores to reconnect later without re-entering the code.
    case paired(macID: String, macName: String, token: String)
    /// Pairing rejected (wrong/expired code, etc.).
    case pairRejected(reason: String)
    /// The current tile list (sent on connect and whenever tiles change).
    case tilesSnapshot(tiles: [Tile])
    /// The current Fiple Bar (curated quick actions; sent on connect and whenever
    /// the bar changes). Icons are resolved on the Mac and carried here.
    case fipleBar(actions: [Action])
    /// Per-action result of a triggered tile.
    case runResult(RunResult)
}

extension ServerMessage: Codable {
    private enum Tag: String, Codable { case paired, pairRejected, tilesSnapshot, fipleBar, runResult }
    private enum CodingKeys: String, CodingKey {
        case type, macID, macName, token, reason, tiles, actions, result
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
        case .pairRejected:
            self = .pairRejected(reason: try c.decode(String.self, forKey: .reason))
        case .tilesSnapshot:
            self = .tilesSnapshot(tiles: try c.decode([Tile].self, forKey: .tiles))
        case .fipleBar:
            self = .fipleBar(actions: try c.decode([Action].self, forKey: .actions))
        case .runResult:
            self = .runResult(try c.decode(RunResult.self, forKey: .result))
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
        case let .pairRejected(reason):
            try c.encode(Tag.pairRejected, forKey: .type)
            try c.encode(reason, forKey: .reason)
        case let .tilesSnapshot(tiles):
            try c.encode(Tag.tilesSnapshot, forKey: .type)
            try c.encode(tiles, forKey: .tiles)
        case let .fipleBar(actions):
            try c.encode(Tag.fipleBar, forKey: .type)
            try c.encode(actions, forKey: .actions)
        case let .runResult(result):
            try c.encode(Tag.runResult, forKey: .type)
            try c.encode(result, forKey: .result)
        }
    }
}
