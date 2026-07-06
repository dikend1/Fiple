#if os(macOS)
import Foundation
import Network
import Testing
@testable import FipleKit

/// Exercises the whole terminal pipeline in one shot: TLS-PSK channel → auth
/// handshake → live pty → encrypted echo. The only piece not covered here is the
/// SwiftTerm renderer on iOS.
@Suite("Terminal service end-to-end", .timeLimit(.minutes(1)))
struct TerminalServiceEndToEndTests {
    private let token = "e2e-token"
    private let password = "e2e-pass"

    @Test("Authenticate then echo a command through the encrypted pty")
    func authThenEcho() async throws {
        let service = TerminalService(
            pairingToken: token,
            passwordRecord: MasterPassword.make(password, iterations: 1_000),
            shellPath: "/bin/cat", shellArguments: ["/bin/cat"] // deterministic echo
        )
        let port = try await service.start()

        let client = TestClient(token: token, port: port)
        try await client.connect()

        // Auth with correct credentials.
        try client.send(.control, MessageCodec.encode(TerminalClientControl.auth(token: token, passwordProof: password)))
        let authReply = try await client.nextControl()
        guard case .authOK = authReply else {
            Issue.record("expected authOK, got \(authReply)")
            return
        }

        // Drive the pty: cat echoes the line back over the encrypted channel.
        try client.send(.data, Data("fipletest\n".utf8))
        try await client.waitForDataContaining("fipletest", timeout: 5)

        service.stop()
        client.close()
    }

    @Test("A wrong master password is rejected and no shell is attached")
    func wrongPasswordRejected() async throws {
        let service = TerminalService(
            pairingToken: token,
            passwordRecord: MasterPassword.make(password, iterations: 1_000),
            shellPath: "/bin/cat", shellArguments: ["/bin/cat"]
        )
        let port = try await service.start()

        let client = TestClient(token: token, port: port)
        try await client.connect()
        try client.send(.control, MessageCodec.encode(TerminalClientControl.auth(token: token, passwordProof: "wrong")))

        let reply = try await client.nextControl()
        #expect(reply == .authFailed(reason: .badPassword))

        service.stop()
        client.close()
    }
}

/// Minimal TLS-PSK terminal client for the tests: connect, send frames, and
/// collect decoded frames off the wire.
private final class TestClient: @unchecked Sendable {
    private let connection: NWConnection
    private let lock = NSLock()
    private var decoder = TerminalFrameDecoder()
    private var controls: [TerminalServerControl] = []
    private var dataText = ""

    init(token: String, port: UInt16) {
        connection = NWConnection(
            host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!,
            using: TerminalTLS.clientParameters(pairingToken: token)
        )
    }

    func connect() async throws {
        let once = OnceLatch()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: if once.claim() { cont.resume() }
                case .failed(let e): if once.claim() { cont.resume(throwing: e) }
                default: break
                }
            }
            connection.start(queue: .global())
        }
        receive()
    }

    enum Kind { case control, data }
    func send(_ kind: Kind, _ payload: Data) throws {
        let type: TerminalFrameType = kind == .control ? .control : .data
        let bytes = try TerminalFrameCodec.frame(TerminalFrame(type: type, payload: payload))
        connection.send(content: bytes, completion: .contentProcessed { _ in })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty, let frames = try? self.decoder.append(data) {
                self.lock.lock()
                for frame in frames {
                    switch frame.type {
                    case .control:
                        if let c = try? MessageCodec.decode(TerminalServerControl.self, from: frame.payload) {
                            self.controls.append(c)
                        }
                    case .data:
                        self.dataText += String(decoding: frame.payload, as: UTF8.self)
                    default:
                        break
                    }
                }
                self.lock.unlock()
            }
            if isComplete || error != nil { return }
            self.receive()
        }
    }

    // Synchronous, non-async accessors so the lock is never touched from an
    // async context (forbidden under strict concurrency).
    private func takeControl() -> TerminalServerControl? {
        lock.lock(); defer { lock.unlock() }
        return controls.isEmpty ? nil : controls.removeFirst()
    }
    private func dataContains(_ needle: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return dataText.contains(needle)
    }

    func nextControl(timeout: TimeInterval = 5) async throws -> TerminalServerControl {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let c = takeControl() { return c }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        throw TransportError.notConnected
    }

    func waitForDataContaining(_ needle: String, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if dataContains(needle) { return }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        throw TransportError.notConnected
    }

    func close() { connection.cancel() }
}

private final class OnceLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if fired { return false }; fired = true; return true }
}
#endif
