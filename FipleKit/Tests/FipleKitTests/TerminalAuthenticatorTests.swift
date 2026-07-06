import Foundation
import Testing
@testable import FipleKit

@Suite("Terminal authenticator")
struct TerminalAuthenticatorTests {
    private let iterations = 1_000
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func makeAuth(
        password: String = "hunter2",
        tokens: Set<String> = ["good-token"],
        maxAttempts: Int = 3
    ) -> TerminalAuthenticator {
        TerminalAuthenticator(
            record: MasterPassword.make(password, iterations: iterations),
            authorizedTokens: tokens,
            throttle: PairingThrottle(maxAttempts: maxAttempts, lockoutDuration: 30)
        )
    }

    @Test("Correct token and password authorize with a session id")
    func happyPath() {
        var auth = makeAuth()
        let decision = auth.authenticate(
            token: "good-token", passwordProof: "hunter2", now: now,
            makeSessionID: { "sess-fixed" }
        )
        #expect(decision == .authorized(.authOK(sessionID: "sess-fixed")))
    }

    @Test("An unknown token is rejected as badToken without consuming an attempt")
    func badToken() {
        var auth = makeAuth()
        let decision = auth.authenticate(
            token: "stranger", passwordProof: "hunter2", now: now,
            makeSessionID: { "x" }
        )
        #expect(decision == .rejected(.badToken))
        #expect(auth.throttle.failedAttempts == 0)
    }

    @Test("A wrong password is rejected and consumes an attempt")
    func badPassword() {
        var auth = makeAuth()
        let decision = auth.authenticate(
            token: "good-token", passwordProof: "wrong", now: now,
            makeSessionID: { "x" }
        )
        #expect(decision == .rejected(.badPassword))
        #expect(auth.throttle.failedAttempts == 1)
    }

    @Test("Repeated wrong passwords lock out on the throttle policy")
    func lockout() {
        var auth = makeAuth(maxAttempts: 3)
        // Three wrong attempts: the third hits the limit and locks out.
        for _ in 0..<2 {
            _ = auth.authenticate(token: "good-token", passwordProof: "wrong", now: now, makeSessionID: { "x" })
        }
        let third = auth.authenticate(token: "good-token", passwordProof: "wrong", now: now, makeSessionID: { "x" })
        #expect(third == .rejected(.lockedOut))

        // Even the correct password is refused while locked out.
        let duringLockout = auth.authenticate(token: "good-token", passwordProof: "hunter2", now: now, makeSessionID: { "x" })
        #expect(duringLockout == .rejected(.lockedOut))
    }

    @Test("After the lockout window lapses, the correct password authorizes again")
    func recoversAfterLockout() {
        var auth = makeAuth(maxAttempts: 2)
        _ = auth.authenticate(token: "good-token", passwordProof: "wrong", now: now, makeSessionID: { "x" })
        let locked = auth.authenticate(token: "good-token", passwordProof: "wrong", now: now, makeSessionID: { "x" })
        #expect(locked == .rejected(.lockedOut))

        let later = now.addingTimeInterval(31)
        let decision = auth.authenticate(
            token: "good-token", passwordProof: "hunter2", now: later,
            makeSessionID: { "sess-recovered" }
        )
        #expect(decision == .authorized(.authOK(sessionID: "sess-recovered")))
    }
}
