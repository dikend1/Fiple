import Foundation

/// A bounded, oldest-dropping buffer of recent pty output.
///
/// The terminal session outlives the TCP connection: when the phone
/// backgrounds and the socket dies, the shell keeps producing output. We retain
/// the most recent bytes so a reattaching client can replay them and restore
/// its screen. The buffer is capped so a runaway process (a `yes` loop) can't
/// grow it without bound — once full, the oldest bytes fall off the front.
public struct ScrollbackBuffer: Sendable {
    /// Default retained window (256 KB) — enough to redraw a full screen plus
    /// recent scrollback, small enough to replay instantly on reattach.
    public static let defaultCapacity = 256 * 1024

    public let capacity: Int
    private var bytes: Data

    public init(capacity: Int = ScrollbackBuffer.defaultCapacity) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        self.bytes = Data()
    }

    /// Number of bytes currently retained.
    public var count: Int { bytes.count }

    /// Append pty output, evicting the oldest bytes past the capacity.
    public mutating func append(_ data: Data) {
        if data.count >= capacity {
            // The new data alone overflows: keep only its tail.
            bytes = data.suffix(capacity)
            return
        }
        bytes.append(data)
        if bytes.count > capacity {
            bytes.removeFirst(bytes.count - capacity)
        }
    }

    /// The retained bytes, oldest first — replayed to a reattaching client.
    public func snapshot() -> Data { bytes }
}
