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

    @Test("A strict (resumeOnly) reconnect resumes a live shell — the phone restore path")
    func strictResumeWorks() async throws {
        let service = makeService()
        let port = try await service.start()

        let first = TerminalClient(host: "127.0.0.1", port: port, pairingToken: token)
        try await first.connect()
        first.authenticate(passwordProof: password, token: token)
        var sessionID: String?
        var firstOutput = ""
        for await event in first.events {
            switch event {
            case let .authenticated(id):
                sessionID = id
                first.send(Data("strict-restore\n".utf8))
            case let .output(data):
                firstOutput += String(decoding: data, as: UTF8.self)
            default: break
            }
            if firstOutput.contains("strict-restore") { break }
        }
        let resumeID = try #require(sessionID)
        first.close()

        // Exactly what a restored phone tab sends: resumeOnly + a resize soon
        // after auth (the deferred replay waits for it).
        let second = TerminalClient(host: "127.0.0.1", port: port, pairingToken: token)
        try await second.connect()
        second.authenticate(passwordProof: password, token: token, resumeSessionID: resumeID, resumeOnly: true)

        var resumedID: String?
        var replay = ""
        var sentResize = false
        for await event in second.events {
            switch event {
            case let .authenticated(id):
                resumedID = id
                if !sentResize { sentResize = true; second.resize(cols: 80, rows: 24) }
            case let .output(data):
                replay += String(decoding: data, as: UTF8.self)
            case .ended:
                Issue.record("strict resume of a LIVE shell must not end the session")
            default: break
            }
            if replay.contains("strict-restore") { break }
        }
        #expect(resumedID == resumeID)
        #expect(replay.contains("strict-restore"))
        second.close()

        // And a strict resume of a DEAD session must end, not spawn a shell.
        service.stop()
        let service2 = makeService()
        let port2 = try await service2.start()
        let third = TerminalClient(host: "127.0.0.1", port: port2, pairingToken: token)
        try await third.connect()
        third.authenticate(passwordProof: password, token: token, resumeSessionID: resumeID, resumeOnly: true)
        var endedForDead = false
        for await event in third.events {
            if case .ended = event { endedForDead = true; break }
            if case .authenticated = event { Issue.record("dead strict resume must not authenticate"); break }
            if case .disconnected = event { break }
        }
        #expect(endedForDead)
        third.close()
        service2.stop()
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
