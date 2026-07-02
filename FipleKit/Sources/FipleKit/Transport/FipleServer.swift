import Foundation
import Network

/// Local-network server: advertises the Mac over Bonjour and surfaces each
/// inbound ``PeerConnection``. Transport only — pairing and tile logic live in
/// the Mac app, which consumes ``newConnections``.
public actor FipleServer {
    private var listener: NWListener?
    private let stream: AsyncStream<PeerConnection>
    private let continuation: AsyncStream<PeerConnection>.Continuation

    /// Cap on simultaneously-open inbound connections. The MVP serves one phone;
    /// a small cap leaves slack for a relaunch overlap while stopping a LAN peer
    /// from exhausting sockets/memory by opening many connections at once.
    private let maxConnections: Int
    private var activeConnections = 0

    private let failureStream: AsyncStream<Void>
    private let failureContinuation: AsyncStream<Void>.Continuation

    public init(maxConnections: Int = 4) {
        self.maxConnections = maxConnections
        (stream, continuation) = AsyncStream.makeStream()
        (failureStream, failureContinuation) = AsyncStream.makeStream()
    }

    /// Connections as they arrive (already started).
    public var newConnections: AsyncStream<PeerConnection> { stream }

    /// Fires when the listener dies after a successful start (interface change,
    /// network reset). The owner should restart the server — otherwise the app
    /// keeps reporting "advertising" over a dead listener.
    public var listenerFailures: AsyncStream<Void> { failureStream }

    /// Number of currently-open accepted connections (diagnostics / tests).
    public var connectionCount: Int { activeConnections }

    /// Starts listening and advertising. Returns the bound TCP port once ready.
    /// Pass `port: .any` (default) to let the OS choose.
    @discardableResult
    public func start(deviceName: String, port: NWEndpoint.Port = .any) async throws -> UInt16 {
        // Restarting (after wake or a listener failure) must not leak the old
        // listener; cancelling it leaves established connections untouched.
        self.listener?.cancel()
        self.listener = nil
        let listener = try NWListener(using: .tcp, on: port)
        listener.service = NWListener.Service(name: deviceName, type: FipleService.bonjourType)

        listener.newConnectionHandler = { [weak self] nwConnection in
            guard let self else { nwConnection.cancel(); return }
            Task { await self.accept(nwConnection) }
        }
        self.listener = listener

        let boundPort: UInt16 = try await withCheckedThrowingContinuation { cont in
            // The continuation must resume exactly once. Network.framework keeps
            // calling this handler for the listener's whole life (a later
            // interface change can deliver `.failed` long after start), so once
            // we resume we swap in a handler that only logs — never touching the
            // already-resumed continuation again.
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = { [weak self] state in
                        if case let .failed(error) = state {
                            FipleLog.discovery.error("listener failed after start: \(error.localizedDescription)")
                            Task { await self?.reportListenerFailure() }
                        }
                    }
                    cont.resume(returning: listener.port?.rawValue ?? 0)
                case let .failed(error):
                    listener.stateUpdateHandler = nil
                    FipleLog.discovery.error("listener failed: \(error.localizedDescription)")
                    cont.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }
        FipleLog.discovery.info("advertising '\(deviceName)' as \(FipleService.bonjourType) on port \(boundPort)")
        return boundPort
    }

    public func stop() {
        FipleLog.discovery.info("server stopped")
        listener?.cancel()
        listener = nil
        activeConnections = 0
        continuation.finish()
    }

    /// Accepts an inbound connection if under the cap, else cancels it. Each
    /// accepted peer decrements the count when it closes, freeing the slot.
    private func accept(_ nwConnection: NWConnection) async {
        guard activeConnections < maxConnections else {
            FipleLog.discovery.notice("connection refused — at capacity (\(self.maxConnections) open)")
            nwConnection.cancel()
            return
        }
        activeConnections += 1
        FipleLog.discovery.info("inbound connection accepted (\(self.activeConnections)/\(self.maxConnections))")
        let peer = PeerConnection(connection: nwConnection)
        // Strangers get a tiny frame cap until they pair; `markAuthenticated()`
        // restores the full limit.
        await peer.limitInboundFrames(to: PeerConnection.preAuthInboundFrameLimit)
        await peer.onClose { [weak self] in
            Task { await self?.connectionClosed() }
        }
        await peer.start()
        continuation.yield(peer)
    }

    private func connectionClosed() {
        if activeConnections > 0 { activeConnections -= 1 }
    }

    private func reportListenerFailure() {
        // Drop the dead listener so a subsequent `start()` begins clean.
        listener?.cancel()
        listener = nil
        failureContinuation.yield(())
    }
}
