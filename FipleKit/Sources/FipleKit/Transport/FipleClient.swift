import Foundation
import Network

/// Local-network client used by the iPhone remote.
///
/// Discovery is silent: ``discover()`` streams Bonjour endpoints in the
/// background and the UI never shows a device list — the pairing code selects
/// and authenticates the right Mac (see PRD `fiple-pairing`).
public actor FipleClient {
    private var browser: NWBrowser?

    public init() {}

    /// Streams discovered Fiple endpoints as they appear on the local network.
    public func discover() -> AsyncStream<NWEndpoint> {
        let (stream, continuation) = AsyncStream.makeStream(of: NWEndpoint.self)
        let descriptor = NWBrowser.Descriptor.bonjour(type: FipleService.bonjourType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: .tcp)

        browser.browseResultsChangedHandler = { results, _ in
            for result in results {
                continuation.yield(result.endpoint)
            }
        }
        browser.stateUpdateHandler = { state in
            if case .failed = state { continuation.finish() }
        }
        continuation.onTermination = { _ in browser.cancel() }

        browser.start(queue: .global(qos: .userInitiated))
        self.browser = browser
        return stream
    }

    public func stopDiscovery() {
        browser?.cancel()
        browser = nil
    }

    /// Opens a framed connection to an endpoint and waits until it is ready.
    public func connect(to endpoint: NWEndpoint) async throws -> PeerConnection {
        let peer = PeerConnection(connection: NWConnection(to: endpoint, using: .tcp))
        await peer.start()
        try await peer.waitUntilReady()
        return peer
    }

    /// Convenience for tests / explicit host:port connections.
    public func connect(host: String, port: UInt16) async throws -> PeerConnection {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        return try await connect(to: endpoint)
    }
}
