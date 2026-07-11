import Foundation

/// Wire-level binary encoding for beam file chunks.
///
/// Chunks are the only hot path on the tile channel: the JSON `beamChunk`
/// message rides its bytes as base64 (+33% on the wire) and makes both peers
/// encode/decode megabyte-scale strings — the bulk of a transfer's CPU time.
/// A binary frame payload skips both. The first byte is a magic tag no JSON
/// message can start with (every JSON payload here begins with `{`), so a
/// receiver branches on it before ever touching the JSON decoder. Everything
/// besides chunks (begin/end/results) stays JSON — they're tiny.
///
/// Payload layout: `[magic 0xFB][16-byte UUID][chunk bytes]`, wrapped in the
/// same length-prefixed frame as every other message.
public enum BeamBinary {
    public static let magic: UInt8 = 0xFB
    private static let headerSize = 1 + 16

    public static func encodeChunk(transferID: UUID, bytes: Data) -> Data {
        var out = Data(capacity: headerSize + bytes.count)
        out.append(magic)
        withUnsafeBytes(of: transferID.uuid) { out.append(contentsOf: $0) }
        out.append(bytes)
        return out
    }

    /// Decodes a binary chunk payload; nil when this isn't one (JSON, etc.).
    public static func decodeChunk(_ payload: Data) -> (transferID: UUID, bytes: Data)? {
        guard payload.count >= headerSize, payload.first == magic else { return nil }
        let idStart = payload.index(payload.startIndex, offsetBy: 1)
        let idEnd = payload.index(idStart, offsetBy: 16)
        var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &uuid) { dest in
            dest.copyBytes(from: payload[idStart ..< idEnd])
        }
        return (UUID(uuid: uuid), Data(payload[idEnd...]))
    }
}
