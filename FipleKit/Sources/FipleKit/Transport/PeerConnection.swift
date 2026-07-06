import Foundation
import Network

/// A single framed, bidirectional message link over one `NWConnection`.
///
/// Owns its `FrameDecoder` and serialises all access through the actor, so the
/// framing state can never be corrupted by concurrent callbacks. Inbound
/// payloads are delivered, in order, via ``messages``.
public actor PeerConnection {
    private let connection: NWConnection
    private var decoder = FrameDecoder()

    private let inbound: AsyncThrowingStream<Data, Error>
    private let inboundContinuation: AsyncThrowingStream<Data, Error>.Continuation

    private var readyWaiters: [CheckedContinuation<Void, Error>] = []
    private var isReady = false
    private var failure: Error?
    private var didFinish = false
    private var onCloseHandler: (@Sendable () -> Void)?

    /// Auth-timeout state: an accepted connection that never completes pairing
    /// is reaped so it can't pin resources indefinitely.
    private var isAuthenticated = false
    private var authTimeoutTask: Task<Void, Never>?

    /// Bounds in-memory buffering of decoded inbound messages so a flooding peer
    /// can't grow memory without limit (the consumer is the only drain).
    private static let inboundBufferLimit = 64

    /// Frame cap applied to peers that haven't authenticated yet. `pair` and
    /// `reconnect` are tiny; anything larger from a stranger is hostile, so a
    /// server shrinks the limit until pairing succeeds (see ``FipleServer``).
    public static let preAuthInboundFrameLimit = 4096

    public init(connection: NWConnection) {
        self.connection = connection
        (inbound, inboundContinuation) = AsyncThrowingStream.makeStream(
            of: Data.self,
            throwing: Error.self,
            bufferingPolicy: .bufferingNewest(Self.inboundBufferLimit)
        )
    }

    /// Ordered stream of decoded payloads (each a complete JSON message body).
    public var messages: AsyncThrowingStream<Data, Error> { inbound }

    /// Begins the connection and receive loop. Safe to call once.
    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleState(state) }
        }
        connection.start(queue: .global(qos: .userInitiated))
        receiveNext()
    }

    /// Suspends until the connection reaches `.ready`, or throws on failure.
    public func waitUntilReady() async throws {
        if isReady { return }
        if let failure { throw failure }
        // Already finished via a clean close (no failure recorded): the ready
        // waiters were drained by `finish` and will never be drained again, so a
        // late caller must not suspend here — it would leak forever.
        if didFinish { throw TransportError.notConnected }
        try await withCheckedThrowingContinuation { readyWaiters.append($0) }
    }

    /// Sends an encodable message as a single length-prefixed frame.
    public func send(_ message: some Encodable) async throws {
        try await sendRaw(MessageCodec.encode(message))
    }

    public func sendRaw(_ payload: Data) async throws {
        let framed = try FrameCodec.frame(payload)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: framed, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    public func close() {
        connection.cancel()
        finish(throwing: nil)
    }

    /// The Mac's resolved address for this live connection, if known. The phone
    /// reuses it to reach the terminal service on the advertised port without a
    /// second Bonjour resolution — the tile channel has already resolved the Mac.
    public func remoteHost() -> String? {
        guard case let .hostPort(host, _)? = connection.currentPath?.remoteEndpoint else { return nil }
        switch host {
        case let .ipv4(address):
            return "\(address)"
        case let .ipv6(address):
            // Keep the %interface zone id: a link-local address (fe80::/10) is
            // unroutable without it, and NWEndpoint.Host parses it back intact.
            return "\(address)"
        case let .name(name, _):
            return name
        @unknown default:
            return nil
        }
    }

    /// Registers a one-shot handler invoked when the connection finishes
    /// (closed, failed, or cancelled). Fires immediately if already finished.
    /// Used by ``FipleServer`` to free a connection slot.
    public func onClose(_ handler: @escaping @Sendable () -> Void) {
        if didFinish { handler() } else { onCloseHandler = handler }
    }

    /// Closes the connection unless ``markAuthenticated()`` is called within
    /// `duration`. Reaps sockets that connect but never complete pairing.
    public func startAuthTimeout(_ duration: Duration) {
        guard !didFinish, !isAuthenticated else { return }
        authTimeoutTask?.cancel()
        authTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            await self?.enforceAuthTimeout()
        }
    }

    /// Caps the size of inbound frames this peer will accept. A frame whose
    /// length prefix exceeds the cap closes the connection.
    public func limitInboundFrames(to bytes: Int) {
        decoder.maxFrameSize = bytes
    }

    /// Marks the connection authenticated, cancelling the auth timeout and
    /// restoring the full inbound frame limit for a peer that was capped
    /// pre-auth.
    public func markAuthenticated() {
        isAuthenticated = true
        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        decoder.maxFrameSize = FrameCodec.maxFrameSize
    }

    private func enforceAuthTimeout() {
        guard !isAuthenticated, !didFinish else { return }
        FipleLog.connection.notice("auth timeout — closing unauthenticated connection")
        close()
    }

    // MARK: - Internals

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            FipleLog.connection.info("ready")
            isReady = true
            readyWaiters.forEach { $0.resume() }
            readyWaiters.removeAll()
        case let .failed(error):
            FipleLog.connection.error("failed: \(error.localizedDescription)")
            finish(throwing: error)
        case .cancelled:
            FipleLog.connection.info("cancelled")
            finish(throwing: nil)
        case .waiting(let error):
            FipleLog.connection.notice("waiting: \(error.localizedDescription)")
        default:
            break
        }
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { await self.handleReceive(data: data, isComplete: isComplete, error: error) }
        }
    }

    private func handleReceive(data: Data?, isComplete: Bool, error: NWError?) {
        if let error {
            FipleLog.connection.error("receive error: \(error.localizedDescription)")
            finish(throwing: error); return
        }
        if let data, !data.isEmpty {
            do {
                for payload in try decoder.append(data) {
                    FipleLog.connection.debug("recv frame: \(payload.count) bytes")
                    if case .dropped = inboundContinuation.yield(payload) {
                        // Dropping a protocol message would silently desync a
                        // stateful session; close so both sides see it.
                        FipleLog.connection.error("inbound buffer overflow — closing connection")
                        connection.cancel()
                        finish(throwing: TransportError.inboundOverflow)
                        return
                    }
                }
            } catch {
                FipleLog.connection.error("frame decode failed: \(error.localizedDescription)")
                finish(throwing: error)
                return
            }
        }
        if isComplete { finish(throwing: nil); return }
        receiveNext()
    }

    private func finish(throwing error: Error?) {
        guard !didFinish else { return }
        didFinish = true
        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        if let error {
            failure = error
            inboundContinuation.finish(throwing: error)
            readyWaiters.forEach { $0.resume(throwing: error) }
        } else {
            inboundContinuation.finish()
            readyWaiters.forEach { $0.resume(throwing: TransportError.notConnected) }
        }
        readyWaiters.removeAll()
        let handler = onCloseHandler
        onCloseHandler = nil
        handler?()
    }
}
