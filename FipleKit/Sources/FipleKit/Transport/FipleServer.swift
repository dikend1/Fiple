import Foundation
import Network

/// Local-network server: advertises the Mac over Bonjour and surfaces each
/// inbound ``PeerConnection``. Transport only — pairing and tile logic live in
/// the Mac app, which consumes ``newConnections``.
public actor FipleServer {
    private var listener: NWListener?
    private let stream: AsyncStream<PeerConnection>
    private let continuation: AsyncStream<PeerConnection>.Continuation

    public init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    /// Connections as they arrive (already started).
    public var newConnections: AsyncStream<PeerConnection> { stream }

    /// Starts listening and advertising. Returns the bound TCP port once ready.
    /// Pass `port: .any` (default) to let the OS choose.
    @discardableResult
    public func start(deviceName: String, port: NWEndpoint.Port = .any) async throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: port)
        listener.service = NWListener.Service(name: deviceName, type: FipleService.bonjourType)

        listener.newConnectionHandler = { [weak self] nwConnection in
            FipleLog.discovery.info("inbound connection accepted")
            let peer = PeerConnection(connection: nwConnection)
            Task {
                await peer.start()
                await self?.deliver(peer)
            }
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
                    listener.stateUpdateHandler = { state in
                        if case let .failed(error) = state {
                            FipleLog.discovery.error("listener failed after start: \(error.localizedDescription)")
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
        continuation.finish()
    }

    private func deliver(_ peer: PeerConnection) {
        continuation.yield(peer)
    }
}
