#if os(macOS)
import Foundation
import Network
import Testing
@testable import FipleKit

/// Exercises the whole terminal pipeline in one shot using the real
/// ``TerminalClient``: TLS-PSK channel → auth handshake → live pty → encrypted
/// echo. The only piece not covered here is the SwiftTerm renderer on iOS.
@Suite("Terminal service end-to-end", .serialized, .timeLimit(.minutes(1)))
struct TerminalServiceEndToEndTests {
    private let token = "e2e-token"
    private let password = "e2e-pass"

    private func makeService() -> TerminalService {
        TerminalService(
            pairingToken: token,
            passwordRecord: MasterPassword.make(password, iterations: 1_000),
            shellPath: "/bin/cat", shellArguments: ["/bin/cat"] // deterministic echo
        )
    }

    @Test("Authenticate then echo a command through the encrypted pty")
    func authThenEcho() async throws {
        let service = makeService()
        let port = try await service.start()

        let client = TerminalClient(host: "127.0.0.1", port: port, pairingToken: token)
        try await client.connect()
        client.authenticate(passwordProof: password, token: token)

        var sawAuth = false
        var output = ""
        // Send the command as soon as we're authenticated, then collect echo.
        for await event in client.events {
            switch event {
            case let .authenticated(sessionID):
                #expect(!sessionID.isEmpty)
                sawAuth = true
                client.send(Data("fipletest\n".utf8))
            case let .output(data):
                output += String(decoding: data, as: UTF8.self)
                if output.contains("fipletest") { client.close() }
            case .authFailed, .ended:
                break
            }
            if output.contains("fipletest") { break }
        }

        #expect(sawAuth)
        #expect(output.contains("fipletest"))
        service.stop()
    }

    @Test("A wrong master password is rejected with no shell attached")
    func wrongPasswordRejected() async throws {
        let service = makeService()
        let port = try await service.start()

        let client = TerminalClient(host: "127.0.0.1", port: port, pairingToken: token)
        try await client.connect()
        client.authenticate(passwordProof: "wrong", token: token)

        var reason: TerminalAuthFailReason?
        for await event in client.events {
            if case let .authFailed(r) = event { reason = r; break }
            if case .ended = event { break }
        }
        #expect(reason == .badPassword)

        client.close()
        service.stop()
    }
}
#endif
