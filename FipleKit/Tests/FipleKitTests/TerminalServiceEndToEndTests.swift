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
            case .authFailed, .ended, .disconnected:
                break
            }
            if output.contains("fipletest") { break }
        }

        #expect(sawAuth)
        #expect(output.contains("fipletest"))
        service.stop()
    }

    @Test("Reconnecting with the session id resumes the shell and replays its buffer")
    func reattachReplaysBuffer() async throws {
        let service = makeService() // default 10-min grace: session survives the gap
        let port = try await service.start()

        // First connection: authenticate, run a command, capture the session id.
        let first = TerminalClient(host: "127.0.0.1", port: port, pairingToken: token)
        try await first.connect()
        first.authenticate(passwordProof: password, token: token)

        var sessionID: String?
        var firstOutput = ""
        for await event in first.events {
            switch event {
            case let .authenticated(id):
                sessionID = id
                first.send(Data("reattach-me\n".utf8))
            case let .output(data):
                firstOutput += String(decoding: data, as: UTF8.self)
            default:
                break
            }
            if firstOutput.contains("reattach-me") { break }
        }
        #expect(firstOutput.contains("reattach-me"))
        let resumeID = try #require(sessionID)

        // Drop the first connection — the shell detaches but keeps running.
        first.close()

        // Second connection: resume the same session; its buffer must replay.
        let second = TerminalClient(host: "127.0.0.1", port: port, pairingToken: token)
        try await second.connect()
        second.authenticate(passwordProof: password, token: token, resumeSessionID: resumeID)

        var resumedID: String?
        var replay = ""
        for await event in second.events {
            switch event {
            case let .authenticated(id):
                resumedID = id
            case let .output(data):
                replay += String(decoding: data, as: UTF8.self)
            default:
                break
            }
            if replay.contains("reattach-me") { break }
        }
        #expect(resumedID == resumeID) // same shell, not a fresh one
        #expect(replay.contains("reattach-me")) // scrollback replayed on reattach

        second.close()
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
