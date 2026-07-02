import Foundation

/// JSON encode/decode for wire messages.
///
/// Encoders/decoders are created per call to stay safe under Swift 6 strict
/// concurrency (no shared mutable `JSONEncoder`).
public enum MessageCodec {
    public static func encode<M: Encodable>(_ message: M) throws -> Data {
        try JSONEncoder().encode(message)
    }

    public static func decode<M: Decodable>(_ type: M.Type, from data: Data) throws -> M {
        try JSONDecoder().decode(type, from: data)
    }

    /// Decodes a wire message, returning `nil` when the payload is a
    /// well-formed envelope of a type this build doesn't know (e.g. a newer
    /// peer). Callers skip `nil` instead of tearing the session down; a
    /// malformed payload of a *known* type still throws.
    public static func decodeIfKnown<M: Decodable & WireTypeTagged>(
        _ type: M.Type, from data: Data
    ) throws -> M? {
        let envelope = try JSONDecoder().decode(WireEnvelope.self, from: data)
        guard M.knownTypes.contains(envelope.type) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }
}

/// A wire message enum that can enumerate the `type` tags it understands,
/// enabling forward-compatible decoding via ``MessageCodec/decodeIfKnown(_:from:)``.
public protocol WireTypeTagged {
    static var knownTypes: Set<String> { get }
}

/// The minimal shape every wire message shares: a `type` tag plus the protocol
/// version stamped by peers running this build or newer.
public struct WireEnvelope: Decodable, Sendable {
    public let type: String
    public let version: Int?
}
