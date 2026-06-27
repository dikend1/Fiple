import Foundation
import Testing
@testable import FipleKit

@Suite("Pairing throttle / lockout")
struct PairingThrottleTests {
    /// A fixed instant; offsets are derived from it so the lockout window is
    /// deterministic (no wall-clock reads).
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    @Test("6 wrong attempts across independent connections trigger lockout")
    func sixWrongAttemptsLockOut() {
        // The throttle is connection-agnostic: calling register() repeatedly is
        // exactly what happens when each guess arrives on its own socket, since
        // ServerController shares one throttle across every connection.
        var throttle = PairingThrottle(maxAttempts: 5, lockoutDuration: 30)

        // Attempts 1–4: rejected, with a decreasing remaining count.
        for expectedRemaining in [4, 3, 2, 1] {
            #expect(throttle.register(matches: false, now: t0) == .rejected(remaining: expectedRemaining))
            #expect(!throttle.isLockedOut(now: t0))
        }
        // Attempt 5: hits the limit → lockout.
        #expect(throttle.register(matches: false, now: t0) == .lockedOut)
        #expect(throttle.isLockedOut(now: t0))
        // Attempt 6 (a brand-new connection): ignored while locked out.
        #expect(throttle.register(matches: false, now: t0) == .ignored)
        #expect(throttle.isLockedOut(now: t0))
    }

    @Test("lockout blocks even a correct code until it expires")
    func lockoutBlocksCorrectCode() {
        var throttle = PairingThrottle(maxAttempts: 3, lockoutDuration: 30)
        _ = throttle.register(matches: false, now: t0)
        _ = throttle.register(matches: false, now: t0)
        #expect(throttle.register(matches: false, now: t0) == .lockedOut)

        // Even the right code is ignored during the lockout window.
        #expect(throttle.register(matches: true, now: t0.addingTimeInterval(10)) == .ignored)

        // After the window, attempts resume — a correct code is accepted.
        #expect(throttle.register(matches: true, now: t0.addingTimeInterval(31)) == .accepted)
    }

    @Test("lockout expiry gives a fresh attempt budget")
    func lockoutExpiryResetsBudget() {
        var throttle = PairingThrottle(maxAttempts: 3, lockoutDuration: 30)
        _ = throttle.register(matches: false, now: t0)
        _ = throttle.register(matches: false, now: t0)
        #expect(throttle.register(matches: false, now: t0) == .lockedOut)

        let later = t0.addingTimeInterval(31)
        #expect(!throttle.isLockedOut(now: later))
        // Full budget again after expiry.
        #expect(throttle.register(matches: false, now: later) == .rejected(remaining: 2))
    }

    @Test("a correct code resets the failure count")
    func successResetsCount() {
        var throttle = PairingThrottle(maxAttempts: 5, lockoutDuration: 30)
        _ = throttle.register(matches: false, now: t0)
        _ = throttle.register(matches: false, now: t0)
        #expect(throttle.register(matches: true, now: t0) == .accepted)
        #expect(throttle.failedAttempts == 0)
        // Subsequent wrong guess starts from a clean budget.
        #expect(throttle.register(matches: false, now: t0) == .rejected(remaining: 4))
    }

    @Test("explicit reset clears attempts but a socket drop must not")
    func resetSemantics() {
        var throttle = PairingThrottle(maxAttempts: 5, lockoutDuration: 30)
        _ = throttle.register(matches: false, now: t0)
        _ = throttle.register(matches: false, now: t0)
        #expect(throttle.failedAttempts == 2)
        // reset() models a successful pair / manual restart — the only sanctioned
        // way to clear the count. (Connection teardown never calls this.)
        throttle.reset()
        #expect(throttle.failedAttempts == 0)
        #expect(throttle.register(matches: false, now: t0) == .rejected(remaining: 4))
    }
}
