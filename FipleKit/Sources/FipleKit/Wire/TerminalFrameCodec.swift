import Foundation

/// Frame type for the terminal channel — a separate, binary protocol from the
/// JSON tile channel (`FrameCodec`). Terminals carry raw pty bytes, so a
/// JSON-only framing would force base64 overhead on every keystroke and screen
/// update. The 1-byte tag lets one connection multiplex shell I/O, window
/// resizes, control messages, and keepalives.
public enum TerminalFrameType: UInt8, Sendable {
    /// Raw pty bytes, either direction.
    case data = 0x01
    /// Terminal window size change (JSON `{cols,rows}`).
    case resize = 0x02
    /// Session control (JSON): auth, attach/detach, exit code, errors.
    case control = 0x03
    /// Keepalive request.
    case ping = 0x04
    /// Keepalive response.
    case pong = 0x05
}

/// One decoded terminal frame: a type tag plus its raw payload.
public struct TerminalFrame: Equatable, Sendable {
    public let type: TerminalFrameType
    public let payload: Data

    public init(type: TerminalFrameType, payload: Data = Data()) {
        self.type = type
        self.payload = payload
    }
}

/// Wire framing for the terminal channel.
///
/// Each frame is `[type: u8][length: u32 big-endian][payload]`. The length cap
/// is shared with `FrameCodec` so both channels reject the same absurd sizes.
public enum TerminalFrameCodec {
    /// Frames a terminal message, refusing anything the receiver would drop.
    public static func frame(_ frame: TerminalFrame) throws -> Data {
        guard frame.payload.count <= FrameCodec.maxFrameSize else {
            throw FrameError.frameTooLarge(frame.payload.count)
        }
        var out = Data(capacity: 5 + frame.payload.count)
        out.append(frame.type.rawValue)
        var length = UInt32(frame.payload.count).bigEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        out.append(frame.payload)
        return out
    }
}

public enum TerminalFrameError: Error, Equatable {
    case unknownType(UInt8)
}

/// Accumulates incoming bytes and yields complete terminal frames as they
/// arrive. Not thread-safe — own it from a single connection.
public struct TerminalFrameDecoder {
    private var buffer = Data()

    /// Largest payload this decoder accepts. A server lowers it for
    /// unauthenticated peers, matching the tile channel's posture.
    public var maxFrameSize: Int

    public init(maxFrameSize: Int = FrameCodec.maxFrameSize) {
        self.maxFrameSize = maxFrameSize
    }

    /// Append newly received bytes and return any complete frames.
    public mutating func append(_ data: Data) throws -> [TerminalFrame] {
        buffer.append(data)
        var frames: [TerminalFrame] = []

        // Header is 1 type byte + 4 length bytes.
        while buffer.count >= 5 {
            let typeByte = buffer[buffer.startIndex]
            let lengthBytes = buffer[buffer.index(buffer.startIndex, offsetBy: 1)..<buffer.index(buffer.startIndex, offsetBy: 5)]
            let length = lengthBytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let len = Int(length)
            if len > maxFrameSize {
                throw FrameError.frameTooLarge(len)
            }
            guard buffer.count >= 5 + len else { break } // wait for more bytes

            guard let type = TerminalFrameType(rawValue: typeByte) else {
                throw TerminalFrameError.unknownType(typeByte)
            }

            let start = buffer.index(buffer.startIndex, offsetBy: 5)
            let end = buffer.index(start, offsetBy: len)
            frames.append(TerminalFrame(type: type, payload: Data(buffer[start..<end])))
            buffer.removeSubrange(buffer.startIndex..<end)
        }
        return frames
    }
}
