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

    public init(connection: NWConnection) {
        self.connection = connection
        (inbound, inboundContinuation) = AsyncThrowingStream.makeStream()
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
        try await withCheckedThrowingContinuation { readyWaiters.append($0) }
    }

    /// Sends an encodable message as a single length-prefixed frame.
    public func send(_ message: some Encodable) async throws {
        try await sendRaw(MessageCodec.encode(message))
    }

    public func sendRaw(_ payload: Data) async throws {
        let framed = FrameCodec.frame(payload)
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

    // MARK: - Internals

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            isReady = true
            readyWaiters.forEach { $0.resume() }
            readyWaiters.removeAll()
        case let .failed(error):
            finish(throwing: error)
        case .cancelled:
            finish(throwing: nil)
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
        if let error { finish(throwing: error); return }
        if let data, !data.isEmpty {
            do {
                for payload in try decoder.append(data) {
                    inboundContinuation.yield(payload)
                }
            } catch {
                finish(throwing: error)
                return
            }
        }
        if isComplete { finish(throwing: nil); return }
        receiveNext()
    }

    private func finish(throwing error: Error?) {
        if let error {
            failure = error
            inboundContinuation.finish(throwing: error)
            readyWaiters.forEach { $0.resume(throwing: error) }
        } else {
            inboundContinuation.finish()
            readyWaiters.forEach { $0.resume(throwing: TransportError.notConnected) }
        }
        readyWaiters.removeAll()
    }
}
