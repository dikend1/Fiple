import Foundation
import Network
import Testing
@testable import FipleKit

@Suite("Transport DoS limits & auth timeout", .timeLimit(.minutes(1)))
struct TransportLimitsTests {
    // MARK: Helpers

    /// Opens a raw TCP connection to the loopback port (no framing/handshake) —
    /// stands in for an arbitrary LAN peer.
    private func rawConnect(port: UInt16) -> NWConnection {
        let conn = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        conn.start(queue: .global(qos: .userInitiated))
        return conn
    }

    /// Polls `condition` until true or the deadline passes.
    private func waitUntil(_ timeout: Duration = .seconds(3), _ condition: @Sendable () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return await condition()
    }

    // MARK: Tests

    @Test("refuses inbound connections beyond the cap")
    func connectionCapEnforced() async throws {
        let server = FipleServer(maxConnections: 2)
        let port = try await server.start(deviceName: "CapMac", port: .any)
        #expect(port != 0)

        // Open one more than the cap.
        let conns = (0..<3).map { _ in rawConnect(port: port) }

        // The server accepts at most 2; the extra is refused (never counted).
        #expect(await waitUntil { await server.connectionCount == 2 })
        // Give the 3rd a chance to be (wrongly) counted — it must not be.
        try? await Task.sleep(for: .milliseconds(200))
        #expect(await server.connectionCount == 2)

        conns.forEach { $0.cancel() }
        await server.stop()
    }

    @Test("closes a connection that never authenticates")
    func authTimeoutClosesUnauthenticated() async throws {
        let server = FipleServer()
        let port = try await server.start(deviceName: "AuthMac", port: .any)

        // Grab the server-side peer for the first connection.
        let serverPeerTask = Task { () -> PeerConnection? in
            for await peer in await server.newConnections { return peer }
            return nil
        }

        let client = FipleClient()
        let clientPeer = try await client.connect(host: "127.0.0.1", port: port)
        let serverPeer = try #require(await serverPeerTask.value)

        // Arm a short auth timeout and never authenticate.
        await serverPeer.startAuthTimeout(.milliseconds(150))

        // The peer's inbound stream should finish once the timeout closes it.
        let ended = await raceCompletion(.seconds(3)) {
            do { for try await _ in await serverPeer.messages {} } catch {}
        }
        #expect(ended)

        await clientPeer.close()
        await server.stop()
    }

    @Test("markAuthenticated cancels the auth timeout (authenticated peer survives)")
    func authenticatedPeerSurvives() async throws {
        let server = FipleServer()
        let port = try await server.start(deviceName: "AuthMac2", port: .any)
        let serverPeerTask = Task { () -> PeerConnection? in
            for await peer in await server.newConnections { return peer }
            return nil
        }
        let client = FipleClient()
        let clientPeer = try await client.connect(host: "127.0.0.1", port: port)
        let serverPeer = try #require(await serverPeerTask.value)

        await serverPeer.startAuthTimeout(.milliseconds(150))
        await serverPeer.markAuthenticated()

        // Stream must NOT end from the (cancelled) timeout within the window.
        let ended = await raceCompletion(.milliseconds(400)) {
            do { for try await _ in await serverPeer.messages {} } catch {}
        }
        #expect(!ended)

        await clientPeer.close()
        await server.stop()
    }

    @Test("frees the connection slot after a peer disconnects")
    func slotFreedAfterDisconnect() async throws {
        let server = FipleServer(maxConnections: 1)
        let port = try await server.start(deviceName: "RelMac", port: .any)

        let first = rawConnect(port: port)
        #expect(await waitUntil { await server.connectionCount == 1 })

        // A second is refused while at capacity.
        let second = rawConnect(port: port)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(await server.connectionCount == 1)

        // Disconnect the first → slot must free.
        first.cancel()
        #expect(await waitUntil { await server.connectionCount == 0 })

        // A fresh connection is now accepted.
        let third = rawConnect(port: port)
        #expect(await waitUntil { await server.connectionCount == 1 })

        second.cancel(); third.cancel()
        await server.stop()
    }

    /// Runs `op` racing a deadline; returns true if `op` completed first.
    private func raceCompletion(_ timeout: Duration, _ op: @escaping @Sendable () async -> Void) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await op(); return true }
            group.addTask { try? await Task.sleep(for: timeout); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}
