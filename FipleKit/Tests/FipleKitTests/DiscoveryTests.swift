import Foundation
import Network
import Testing
@testable import FipleKit

@Suite("Discovery stability", .timeLimit(.minutes(1)))
struct DiscoveryTests {
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

    // MARK: Pure dedupe seam (deterministic, no network)

    @Test("dedupe key collapses the same Mac to one key")
    func dedupeKeyIdentifiesSameMac() {
        let a1 = NWEndpoint.service(name: "Maks-Mac", type: "_fiple._tcp", domain: "local.", interface: nil)
        let a2 = NWEndpoint.service(name: "Maks-Mac", type: "_fiple._tcp", domain: "local.", interface: nil)
        let other = NWEndpoint.service(name: "Other-Mac", type: "_fiple._tcp", domain: "local.", interface: nil)
        #expect(FipleClient.dedupeKey(a1) == FipleClient.dedupeKey(a2))
        #expect(FipleClient.dedupeKey(a1) != FipleClient.dedupeKey(other))
    }

    // MARK: Stream lifecycle (no dependency on discovering anything)

    @Test("stopDiscovery finishes the stream")
    func stopDiscoveryFinishesStream() async throws {
        let client = FipleClient()
        let stream = await client.discover()
        let consumed = Task { for await _ in stream {} }

        try await Task.sleep(for: .milliseconds(200)) // let the browser spin up
        await client.stopDiscovery()

        let ended = await raceCompletion(.seconds(3)) { await consumed.value }
        #expect(ended)
    }

    @Test("re-entering discover cancels the previous browser and finishes its stream")
    func reentrantDiscoverFinishesPreviousStream() async throws {
        let client = FipleClient()
        let first = await client.discover()
        let firstConsumed = Task { for await _ in first {} }

        try await Task.sleep(for: .milliseconds(200))
        _ = await client.discover() // must cancel the first browser

        let ended = await raceCompletion(.seconds(3)) { await firstConsumed.value }
        #expect(ended)
        await client.stopDiscovery()
    }

    // MARK: End-to-end (real Bonjour on the local host)

    @Test("discovers an advertised Mac exactly once")
    func discoversAdvertisedMacOnce() async throws {
        let unique = "FipleTest-\(UUID().uuidString.prefix(8))"
        let server = FipleServer()
        _ = try await server.start(deviceName: unique, port: .any)

        let client = FipleClient()
        let stream = await client.discover()

        // Collect matches for our uniquely-named service until the stream ends.
        let collector = Task { () -> Int in
            var count = 0
            for await endpoint in stream {
                if case let .service(name, _, _, _) = endpoint, name == unique { count += 1 }
            }
            return count
        }

        try await Task.sleep(for: .seconds(3)) // window for Bonjour to resolve + report
        await client.stopDiscovery()            // finishes the stream → collector returns
        let matches = await collector.value
        await server.stop()

        #expect(matches >= 1) // discovery works
        #expect(matches == 1) // and the same Mac isn't duplicated
    }
}
