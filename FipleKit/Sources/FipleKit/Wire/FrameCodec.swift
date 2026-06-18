import Foundation

/// Length-prefixed framing for the TCP message stream.
///
/// Each frame is a 4-byte big-endian unsigned length followed by that many
/// bytes of JSON payload. This lets the transport recover discrete messages
/// from a byte stream that may split or coalesce them.
public enum FrameCodec {
    /// Hard cap to reject absurd/hostile length prefixes (8 MB).
    public static let maxFrameSize = 8 * 1024 * 1024

    public static func frame(_ payload: Data) -> Data {
        var out = Data(capacity: 4 + payload.count)
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        out.append(payload)
        return out
    }
}

public enum FrameError: Error, Equatable {
    case frameTooLarge(Int)
}

/// Accumulates incoming bytes and yields complete payloads as they arrive.
///
/// Not thread-safe by itself — own it from a single actor/connection.
public struct FrameDecoder {
    private var buffer = Data()

    public init() {}

    /// Append newly received bytes and return any complete payloads.
    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var payloads: [Data] = []

        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let len = Int(length)
            if len > FrameCodec.maxFrameSize {
                throw FrameError.frameTooLarge(len)
            }
            guard buffer.count >= 4 + len else { break } // wait for more bytes

            let start = buffer.index(buffer.startIndex, offsetBy: 4)
            let end = buffer.index(start, offsetBy: len)
            payloads.append(Data(buffer[start..<end]))
            buffer.removeSubrange(buffer.startIndex..<end)
        }
        return payloads
    }
}
