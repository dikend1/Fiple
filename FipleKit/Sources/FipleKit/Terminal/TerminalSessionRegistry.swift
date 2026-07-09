#if os(macOS)
import Foundation

/// A shell that outlives the socket that started it.
///
/// iOS tears down the TCP connection seconds after the app backgrounds, but the
/// build you kicked off should keep running. A `ShellSession` owns the pty and a
/// scrollback buffer independently of any connection: when the phone drops, the
/// session detaches and a grace timer starts; if the phone reattaches in time it
/// replays the buffer and rewires output; if not, the shell gets SIGHUP.
///
/// Confined to the terminal service's serial `queue` — no internal locking.
final class ShellSession: @unchecked Sendable {
    let id: String
    private let pty: PTYSession
    private let queue: DispatchQueue
    /// Read fresh on each detach so a live grace-period change (Settings picker)
    /// applies without restarting the service or killing running shells.
    private let graceProvider: () -> TimeInterval
    private var scrollback = ScrollbackBuffer()
    /// The attached connection's frame sink, or nil while detached.
    private var sink: ((TerminalFrame) -> Void)?
    private var graceItem: DispatchWorkItem?
    private var onExpired: ((String) -> Void)?

    init(id: String, pty: PTYSession, queue: DispatchQueue, graceProvider: @escaping () -> TimeInterval, onExpired: @escaping (String) -> Void) {
        self.id = id
        self.pty = pty
        self.queue = queue
        self.graceProvider = graceProvider
        self.onExpired = onExpired

        pty.onOutput = { [weak self] data in
            guard let self else { return }
            self.queue.async {
                self.scrollback.append(data)
                self.sink?(TerminalFrame(type: .data, payload: data))
            }
        }
        pty.onExit = { [weak self] code in
            guard let self else { return }
            self.queue.async {
                if let payload = try? MessageCodec.encode(TerminalServerControl.sessionEnded(exitCode: code)) {
                    self.sink?(TerminalFrame(type: .control, payload: payload))
                }
                self.expire()
            }
        }
    }

    /// Attaches a connection: cancels any pending grace expiry, wires output to
    /// `sink`, and replays the buffered scrollback so the phone redraws.
    func attach(sink: @escaping (TerminalFrame) -> Void) {
        graceItem?.cancel()
        graceItem = nil
        self.sink = sink
        let buffered = scrollback.snapshot()
        if !buffered.isEmpty {
            sink(TerminalFrame(type: .data, payload: buffered))
        }
    }

    /// Detaches the current connection and starts the grace countdown. The shell
    /// keeps running; if no one reattaches before it lapses, SIGHUP ends it.
    func detach() {
        sink = nil
        let grace = graceProvider()
        // A non-finite grace means "keep running until explicitly closed".
        guard grace.isFinite else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pty.hangup()
            self.expire()
        }
        graceItem = item
        queue.asyncAfter(deadline: .now() + grace, execute: item)
    }

    func write(_ data: Data) { pty.write(data) }
    func resize(cols: Int, rows: Int) { pty.resize(cols: cols, rows: rows) }

    /// Tears the session down for good.
    func close() {
        graceItem?.cancel()
        graceItem = nil
        sink = nil
        pty.close()
    }

    private func expire() {
        let notify = onExpired
        onExpired = nil // fire once
        close()
        notify?(id)
    }
}

/// Owns the live shell sessions on the Mac, keyed by id, so a reconnecting phone
/// can resume the shell it started. One session per paired device in Phase 1.
final class TerminalSessionRegistry: @unchecked Sendable {
    private let queue: DispatchQueue
    /// Current detach grace, read live by each shell so a Settings change takes
    /// effect immediately without restarting the service.
    var graceInterval: TimeInterval
    private let shellPath: String?
    private let shellArguments: [String]?
    private var sessions: [String: ShellSession] = [:]

    init(queue: DispatchQueue, graceInterval: TimeInterval, shellPath: String?, shellArguments: [String]?) {
        self.queue = queue
        self.graceInterval = graceInterval
        self.shellPath = shellPath
        self.shellArguments = shellArguments
    }

    /// Returns a live session for `id`, or nil if it never existed / already
    /// expired. Call on `queue`.
    func session(id: String) -> ShellSession? { sessions[id] }

    /// Spawns a fresh shell session. Call on `queue`.
    func create() throws -> ShellSession {
        let id = UUID().uuidString
        let pty = try PTYSession(shellPath: shellPath, arguments: shellArguments)
        let session = ShellSession(
            id: id, pty: pty, queue: queue,
            graceProvider: { [weak self] in self?.graceInterval ?? 1800 },
            onExpired: { [weak self] expiredID in self?.sessions[expiredID] = nil }
        )
        sessions[id] = session
        return session
    }

    /// Ends one session for good (the phone closed its tab). Call on `queue`.
    func end(id: String) {
        sessions[id]?.close()
        sessions[id] = nil
    }

    /// Closes and drops every session (service stopping). Call on `queue`.
    func closeAll() {
        for session in sessions.values { session.close() }
        sessions.removeAll()
    }
}
#endif
