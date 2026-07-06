import FipleKit
import Foundation
import Observation

/// The phone-side terminal session controller. Stable across reconnects: it owns
/// the current `TerminalClient`, is the *single* consumer of its event stream,
/// and re-establishes the channel (resuming the same Mac shell) when the app
/// returns from the background.
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
        case failed(String)
        case ended
    }

    private(set) var phase: Phase = .connecting
    /// Bumped on every successful (re)connect, so the terminal view can force a
    /// fresh emulator and cleanly redraw the replayed scrollback.
    private(set) var generation = 0

    private let host: String
    private let port: UInt16
    private let token: String
    private let password: String

    /// The Mac shell id to resume; nil on first connect, set once authenticated.
    private var resumeSessionID: String?
    @ObservationIgnored private var client: TerminalClient?
    @ObservationIgnored private var pumpTask: Task<Void, Never>?

    /// Set by the terminal view to receive shell output bytes.
    @ObservationIgnored var outputHandler: (@MainActor (Data) -> Void)?

    init(host: String, port: UInt16, token: String, password: String) {
        self.host = host
        self.port = port
        self.token = token
        self.password = password
    }

    /// Opens the channel and authenticates. Idempotent enough to call again for
    /// a foreground reconnect — it tears down any prior client first.
    func connect() async {
        pumpTask?.cancel()
        client?.close()

        phase = .connecting
        let client = TerminalClient(host: host, port: port, pairingToken: token)
        self.client = client
        do {
            try await client.connect()
        } catch {
            phase = .failed("Could not reach the Mac’s terminal service.")
            return
        }
        phase = .authenticating
        client.authenticate(passwordProof: password, token: token, resumeSessionID: resumeSessionID)
        pump(client)
    }

    /// Re-establishes the session after returning from the background, resuming
    /// the same Mac shell. No-op while a connection is still live/connecting.
    func reconnectIfNeeded() async {
        switch phase {
        case .ready, .connecting, .authenticating:
            return // still attached (or attaching)
        case .failed, .ended:
            await connect()
        }
    }

    func send(_ data: Data) { client?.send(data) }
    func resize(cols: Int, rows: Int) { client?.resize(cols: cols, rows: rows) }

    func close() {
        pumpTask?.cancel()
        pumpTask = nil
        client?.close()
        client = nil
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
                    self.outputHandler?(data)
                case let .authFailed(reason):
                    self.phase = .failed(Self.message(for: reason))
                case .ended:
                    // Backgrounding kills the socket; keep resumeSessionID so a
                    // foreground reconnect resumes the same shell.
                    if self.phase == .ready { self.phase = .ended }
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
