import FipleKit
import Foundation
import Observation

/// The phone-side terminal session controller. Stable across reconnects: it owns
/// the current `TerminalClient`, is the *single* consumer of its event stream,
/// and re-establishes the channel (resuming the same Mac shell) when the link
/// drops — the Mac sleeps, Wi-Fi blips, or the app returns from the background.
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
    /// clear a stale saved password on `.badPassword` and offer a retry).
    private(set) var lastAuthFailReason: TerminalAuthFailReason?
    /// Bumped on every successful (re)connect, so the terminal view can force a
    /// fresh emulator and cleanly redraw the replayed scrollback.
    private(set) var generation = 0

    private let host: String
    private let port: UInt16
    private let token: String
    private var password: String
    /// Seconds between reconnect attempts while the Mac is unreachable.
    private let retryInterval: TimeInterval = 3

    /// The Mac shell id to resume; nil on first connect, set once authenticated.
    private var resumeSessionID: String?
    private var backgrounded = false
    private var closed = false
    @ObservationIgnored private var client: TerminalClient?
    @ObservationIgnored private var pumpTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    /// Set by the terminal view to receive shell output bytes.
    @ObservationIgnored var outputHandler: (@MainActor (Data) -> Void)?

    init(host: String, port: UInt16, token: String, password: String) {
        self.host = host
        self.port = port
        self.token = token
        self.password = password
    }

    /// First connection.
    func connect() async {
        phase = .connecting
        await attempt()
    }

    /// Re-authenticate with a corrected password (from the inline retry field),
    /// without leaving the terminal screen.
    func retry(withPassword newPassword: String) {
        password = newPassword
        lastAuthFailReason = nil
        retryTask?.cancel()
        Task { await connect() }
    }

    /// Called on scene-phase changes. iOS kills the socket seconds after the app
    /// backgrounds, so on returning to the foreground we resume the shell.
    func scenePhaseChanged(active: Bool) {
        if active {
            // Returning to the foreground: the socket was killed while backgrounded,
            // so resume the shell. No-op on the very first activation.
            if backgrounded, !closed {
                backgrounded = false
                startReconnectLoop()
            }
        } else {
            backgrounded = true
        }
    }

    func send(_ data: Data) { client?.send(data) }
    func resize(cols: Int, rows: Int) { client?.resize(cols: cols, rows: rows) }

    func close() {
        closed = true
        retryTask?.cancel(); retryTask = nil
        pumpTask?.cancel(); pumpTask = nil
        client?.close(); client = nil
    }

    // MARK: - Connection

    /// One connection attempt: open the channel, authenticate, start pumping.
    /// Leaves `phase` for the pump to advance to `.ready` on success.
    private func attempt() async {
        pumpTask?.cancel()
        client?.close()

        let client = TerminalClient(host: host, port: port, pairingToken: token)
        self.client = client
        do {
            try await client.connect(timeout: 8)
        } catch {
            return // couldn't reach the Mac; the retry loop tries again
        }
        guard !closed else { client.close(); return }
        client.authenticate(passwordProof: password, token: token, resumeSessionID: resumeSessionID)
        pump(client)
    }

    /// Keeps reconnecting (resuming the shell) until it succeeds or the screen
    /// closes — so a sleeping Mac coming back online reconnects on its own.
    private func startReconnectLoop() {
        guard !closed else { return }
        if phase != .reconnecting { phase = .reconnecting }
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            while let self, !self.closed, self.phase != .ready {
                await self.attempt()
                // Let the auth handshake land before deciding to retry.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if self.phase == .ready { break }
                try? await Task.sleep(for: .seconds(self.retryInterval))
            }
        }
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
                    self.retryTask?.cancel()
                    self.phase = .ready
                case let .output(data):
                    self.outputHandler?(data)
                case let .authFailed(reason):
                    self.lastAuthFailReason = reason
                    self.retryTask?.cancel()
                    self.phase = .failed(Self.message(for: reason))
                case .ended:
                    // The shell process exited — nothing to resume.
                    self.retryTask?.cancel()
                    self.phase = .ended
                case .disconnected:
                    // The link dropped (Mac asleep / Wi-Fi). Keep resumeSessionID
                    // and retry — unless the user closed the screen.
                    if !self.closed { self.startReconnectLoop() }
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
