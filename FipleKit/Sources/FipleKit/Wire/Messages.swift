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
}

extension ClientMessage: Codable {
    private enum Tag: String, Codable { case pair, reconnect, run }
    private enum CodingKeys: String, CodingKey { case type, code, token, tileID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Tag.self, forKey: .type) {
        case .pair: self = .pair(code: try c.decode(String.self, forKey: .code))
        case .reconnect: self = .reconnect(token: try c.decode(String.self, forKey: .token))
        case .run: self = .run(tileID: try c.decode(UUID.self, forKey: .tileID))
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
    /// Per-action result of a triggered tile.
    case runResult(RunResult)
}

extension ServerMessage: Codable {
    private enum Tag: String, Codable { case paired, pairRejected, tilesSnapshot, runResult }
    private enum CodingKeys: String, CodingKey {
        case type, macID, macName, token, reason, tiles, result
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
        case let .runResult(result):
            try c.encode(Tag.runResult, forKey: .type)
            try c.encode(result, forKey: .result)
        }
    }
}
