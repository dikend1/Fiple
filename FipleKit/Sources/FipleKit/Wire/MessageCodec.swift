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
}
