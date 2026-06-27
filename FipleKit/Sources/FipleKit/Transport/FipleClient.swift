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
            FipleLog.discovery.info("browse results changed: \(results.count) endpoint(s)")
            for result in results {
                continuation.yield(result.endpoint)
            }
        }
        browser.stateUpdateHandler = { state in
            if case let .failed(error) = state {
                FipleLog.discovery.error("browser failed: \(error.localizedDescription)")
                continuation.finish()
            }
        }
        continuation.onTermination = { _ in browser.cancel() }

        FipleLog.discovery.info("discovery started for \(FipleService.bonjourType)")
        browser.start(queue: .global(qos: .userInitiated))
        self.browser = browser
        return stream
    }

    public func stopDiscovery() {
        FipleLog.discovery.info("discovery stopped")
        browser?.cancel()
        browser = nil
    }

    /// Opens a framed connection to an endpoint and waits until it is ready.
    ///
    /// Fails after `timeout` instead of hanging forever: `NWConnection` reports
    /// an unreachable host (Mac asleep/off, wrong port) as `.waiting`, which
    /// never resolves on its own, so without a deadline `waitUntilReady()` would
    /// suspend indefinitely.
    public func connect(to endpoint: NWEndpoint, timeout: Duration = .seconds(10)) async throws -> PeerConnection {
        FipleLog.connection.info("connecting to \(String(describing: endpoint))")
        let peer = PeerConnection(connection: NWConnection(to: endpoint, using: .tcp))
        await peer.start()

        // Race readiness against a deadline. An unreachable host sits in
        // `.waiting` forever, so `waitUntilReady()` would never return on its
        // own. The timer closes the peer on expiry, which resumes the ready
        // waiter (`close()` → `finish`), so there is no leaked continuation and
        // no structured-task-group drain to deadlock on.
        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            FipleLog.connection.error("connect timed out")
            await peer.close()
        }

        do {
            try await peer.waitUntilReady()
            timeoutTask.cancel()
        } catch {
            timeoutTask.cancel()
            FipleLog.connection.error("connect failed: \(error.localizedDescription)")
            await peer.close()
            throw error
        }
        FipleLog.connection.info("connected")
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
