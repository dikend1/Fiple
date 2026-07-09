import FipleKit
import Foundation
import Observation

/// The phone-side terminal session controller. Stable across reconnects: it owns
/// the current `TerminalClient`, is the *single* consumer of its event stream,
/// and re-establishes the channel (resuming the same Mac shell) when the link
/// drops — the Mac sleeps, Wi-Fi blips, or the app returns from the background.
///
/// All reconnection funnels through ONE serialized loop (`connectLoop`) with
/// backoff and a cap, so a dead port can never trigger a connection storm.
///
/// The SwiftTerm view binds to this — feeding from `outputHandler` and sending
/// through `send`/`resize` — so a reconnect swaps the underlying client without
/// the view knowing.
@MainActor
@Observable
final class TerminalSession {
    enum Phase: Equatable {
        case connecting
        case authenticating
        case ready
        /// The link dropped (Mac asleep / network) and we're retrying.
        case reconnecting
        case failed(String)
        /// The shell itself exited — nothing to resume.
        case ended
    }

    private(set) var phase: Phase = .connecting
    /// The reason for the most recent auth rejection, so the UI can react (e.g.
    /// show the inline password field on `.badPassword`).
    private(set) var lastAuthFailReason: TerminalAuthFailReason?
    /// Bumped on every successful (re)connect, so the terminal view can force a
    /// fresh emulator and cleanly redraw the replayed scrollback.
    private(set) var generation = 0
    /// When shell output last arrived — the session-menu "unseen output" signal
    /// for tabs running in the background.
    private(set) var lastOutputAt: Date?

    private let host: String
    private let port: UInt16
    private let token: String
    private var password: String

    /// The Mac shell id to resume; nil on first connect, set once authenticated.
    private var resumeSessionID: String?
    private var backgrounded = false
    private var closed = false
    /// A Face-ID password was valid before, so a rejection right after an app
    /// restart is likely the Mac still settling — retry a few times before
    /// surfacing the inline password field.
    private var authRetriesLeft: Int
    /// The single connection loop is running; new triggers must not start another.
    private var loopRunning = false
    /// Set when the current attempt's auth was rejected as a real (non-retryable)
    /// failure, so the loop stops instead of retrying.
    private var stopReason: String?

    @ObservationIgnored private var client: TerminalClient?
    @ObservationIgnored private var pumpTask: Task<Void, Never>?
    @ObservationIgnored private var loopTask: Task<Void, Never>?

    /// Set by the terminal view to receive shell output bytes.
    @ObservationIgnored var outputHandler: (@MainActor (Data) -> Void)?

    init(host: String, port: UInt16, token: String, password: String, passwordPrevalidated: Bool = false) {
        self.host = host
        self.port = port
        self.token = token
        self.password = password
        self.authRetriesLeft = passwordPrevalidated ? 3 : 0
    }

    /// First connection.
    func connect() async {
        startLoop(firstTime: true)
    }

    /// Re-authenticate with a corrected password (from the inline retry field).
    func retry(withPassword newPassword: String) {
        password = newPassword
        authRetriesLeft = 3
        lastAuthFailReason = nil
        stopReason = nil
        startLoop(firstTime: true)
    }

    /// iOS kills the socket seconds after the app backgrounds, so on returning to
    /// the foreground we resume the shell.
    func scenePhaseChanged(active: Bool) {
        if active {
            if backgrounded, !closed { backgrounded = false; startLoop(firstTime: false) }
        } else {
            backgrounded = true
        }
    }

    func send(_ data: Data) { client?.send(data) }
    func resize(cols: Int, rows: Int) { client?.resize(cols: cols, rows: rows) }

    /// Closes this tab for good: tells the Mac to end the shell now (instead of
    /// letting it idle through the grace period), then tears the channel down.
    func endShell() {
        if let id = resumeSessionID { client?.endSession(sessionID: id) }
        close()
    }

    func close() {
        closed = true
        loopTask?.cancel(); loopTask = nil
        pumpTask?.cancel(); pumpTask = nil
        client?.close(); client = nil
    }

    // MARK: - The one reconnection loop

    /// Ensures the single connect loop is running. Idempotent — a second call
    /// while it's already running is a no-op, which is what stops storms.
    private func startLoop(firstTime: Bool) {
        guard !closed, !loopRunning else { return }
        loopRunning = true
        stopReason = nil
        phase = firstTime ? .connecting : .reconnecting

        loopTask = Task { [weak self] in
            var attempt = 0
            while true {
                guard let self, !self.closed else { break }
                // Stop on a terminal state.
                if self.phase == .ready || self.phase == .ended { break }
                if let reason = self.stopReason { self.phase = .failed(reason); break }
                if attempt >= 15 {
                    self.phase = .failed("Couldn’t reach your Mac’s terminal. Make sure it’s awake and on the same Wi-Fi.")
                    break
                }
                attempt += 1

                await self.attemptOnce()
                // Wait for the auth result (or a drop) to land — but poll, so a
                // fast success opens the terminal in ~100 ms instead of a flat
                // 2-second stall.
                for _ in 0 ..< 30 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    if self.closed || self.phase == .ready || self.phase == .ended
                        || self.stopReason != nil { break }
                }

                if self.closed { break }
                if self.phase == .ready || self.phase == .ended { break }
                if let reason = self.stopReason { self.phase = .failed(reason); break }

                // Back off before the next attempt (1.5s → capped 8s).
                if self.phase != .reconnecting { self.phase = .reconnecting }
                let backoff = min(Double(attempt) * 1.5, 8)
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            }
            self?.loopRunning = false
        }
    }

    /// One connection attempt: open the channel, authenticate, start pumping.
    /// The pump advances `phase` (to `.ready`, `.ended`) or sets `stopReason`.
    private func attemptOnce() async {
        pumpTask?.cancel()
        client?.close()

        let client = TerminalClient(host: host, port: port, pairingToken: token)
        self.client = client
        do {
            try await client.connect(timeout: 6)
        } catch {
            return // unreachable; the loop backs off and retries
        }
        guard !closed else { client.close(); return }
        if phase != .ready { phase = .authenticating }
        client.authenticate(passwordProof: password, token: token, resumeSessionID: resumeSessionID)
        pump(client)
    }

    private func pump(_ client: TerminalClient) {
        pumpTask?.cancel()
        pumpTask = Task { [weak self] in
            for await event in client.events {
                guard let self else { return }
                switch event {
                case let .authenticated(sessionID):
                    self.resumeSessionID = sessionID
                    self.generation += 1
                    self.phase = .ready
                case let .output(data):
                    self.lastOutputAt = Date()
                    self.outputHandler?(data)
                case let .authFailed(reason):
                    self.lastAuthFailReason = reason
                    // A pre-validated (Face ID) password rejected right after a
                    // restart is usually a settling Mac — let the loop retry.
                    // Otherwise it's a real failure: stop the loop.
                    if reason == .badPassword, self.authRetriesLeft > 0 {
                        self.authRetriesLeft -= 1
                    } else {
                        self.stopReason = Self.message(for: reason)
                    }
                case .ended:
                    self.phase = .ended
                case .disconnected:
                    // The link dropped mid-session. If the loop already exited
                    // (we were connected), start it again; otherwise it's already
                    // running and will retry on its own.
                    if !self.closed, self.phase == .ready {
                        self.startLoop(firstTime: false)
                    }
                }
            }
        }
    }

    private static func message(for reason: TerminalAuthFailReason) -> String {
        switch reason {
        case .badToken: return "This device isn’t paired with the Mac anymore."
        case .badPassword: return "Wrong master password."
        case .lockedOut: return "Too many attempts. Try again in a moment."
        case .serviceDisabled: return "Terminal is turned off on the Mac."
        }
    }
}
