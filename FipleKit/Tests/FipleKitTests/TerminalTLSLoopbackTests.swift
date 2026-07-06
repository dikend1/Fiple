import Foundation
import Network
import Testing
@testable import FipleKit

@Suite("Terminal TLS loopback", .timeLimit(.minutes(1)))
struct TerminalTLSLoopbackTests {
    /// Brings up a TLS-PSK listener on localhost and connects with matching
    /// parameters, then pushes one terminal DATA frame through the encrypted
    /// channel and checks it arrives intact.
    @Test("Matching PSK establishes an encrypted channel and carries a frame")
    func matchingPSKRoundTrip() async throws {
        let token = "pairing-token-xyz"
        let listener = try NWListener(using: TerminalTLS.serverParameters(pairingToken: token))

        let payload = Data("echo hello\n".utf8)
        let framed = try TerminalFrameCodec.frame(TerminalFrame(type: .data, payload: payload))

        // Server: accept one connection and send the framed bytes once ready.
        // The connection must outlive the handler, so retain it in a box.
        let held = Box()
        listener.newConnectionHandler = { conn in
            held.connection = conn
            conn.stateUpdateHandler = { state in
                if case .ready = state {
                    conn.send(content: framed, completion: .contentProcessed { _ in })
                }
            }
            conn.start(queue: .global())
        }
        listener.start(queue: .global())

        // Wait for the listener to bind and learn its port.
        let port = try await waitForPort(listener)

        // Client: connect with the same PSK, read one frame back.
        let client = NWConnection(
            host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!,
            using: TerminalTLS.clientParameters(pairingToken: token)
        )
        let got = try await firstFrame(on: client)
        listener.cancel()
        client.cancel()

        var decoder = TerminalFrameDecoder()
        let frames = try decoder.append(got)
        #expect(frames.first == TerminalFrame(type: .data, payload: payload))
    }

    /// A client with a PSK derived from a different token cannot complete the
    /// handshake — the connection never reaches `.ready`.
    @Test("A mismatched PSK fails the handshake")
    func mismatchedPSKFails() async throws {
        let listener = try NWListener(using: TerminalTLS.serverParameters(pairingToken: "server-token"))
        listener.newConnectionHandler = { $0.start(queue: .global()) }
        listener.start(queue: .global())
        let port = try await waitForPort(listener)

        let client = NWConnection(
            host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!,
            using: TerminalTLS.clientParameters(pairingToken: "phone-token") // different!
        )
        let reachedReady = await reachesReady(client, timeout: 5)
        listener.cancel()
        client.cancel()
        #expect(reachedReady == false)
    }

    // MARK: - helpers

    /// Retains a connection past the escaping handler that created it.
    private final class Box: @unchecked Sendable {
        var connection: NWConnection?
    }

    /// Thread-safe "resume the continuation exactly once" latch, usable from the
    /// concurrent connection callbacks under strict concurrency.
    private final class OnceGuard: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false
        /// Returns true the first time only.
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if fired { return false }
            fired = true
            return true
        }
    }

    private func waitForPort(_ listener: NWListener) async throws -> UInt16 {
        for _ in 0..<100 {
            if let port = listener.port?.rawValue, port != 0 { return port }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw TransportError.notConnected
    }

    private func firstFrame(on connection: NWConnection) async throws -> Data {
        let guardOnce = OnceGuard()
        return try await withCheckedThrowingContinuation { cont in
            connection.stateUpdateHandler = { state in
                if case .failed(let error) = state, guardOnce.claim() { cont.resume(throwing: error) }
            }
            connection.start(queue: .global())
            func receive() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                    if let data, !data.isEmpty, guardOnce.claim() { cont.resume(returning: data); return }
                    if let error, guardOnce.claim() { cont.resume(throwing: error); return }
                    receive()
                }
            }
            receive()
        }
    }

    private func reachesReady(_ connection: NWConnection, timeout: TimeInterval) async -> Bool {
        let guardOnce = OnceGuard()
        return await withCheckedContinuation { cont in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if guardOnce.claim() { cont.resume(returning: true) }
                case .failed, .cancelled:
                    if guardOnce.claim() { cont.resume(returning: false) }
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if guardOnce.claim() { cont.resume(returning: false) }
            }
        }
    }
}
