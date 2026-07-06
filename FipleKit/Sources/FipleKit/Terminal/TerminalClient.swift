import Foundation
import Network

/// The phone's side of the terminal channel: opens the TLS-PSK connection, runs
/// the auth handshake, and bridges the encrypted socket to a terminal renderer.
///
/// UI-agnostic on purpose — the iOS app feeds ``Event/output(_:)`` into a
/// SwiftTerm view and forwards keystrokes to ``send(_:)``, but the whole flow is
/// exercised headless in tests against ``TerminalService``.
public final class TerminalClient: @unchecked Sendable {
    /// Things the channel reports upward, in arrival order.
    public enum Event: Sendable, Equatable {
        /// Auth succeeded; the session id to reattach to later.
        case authenticated(sessionID: String)
        /// Auth rejected, with a typed reason.
        case authFailed(TerminalAuthFailReason)
        /// Shell output bytes to feed the terminal renderer.
        case output(Data)
        /// The shell exited (or the channel ended), with its code if known.
        case ended(exitCode: Int32?)
    }

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.fiple.terminal.client")
    private var decoder = TerminalFrameDecoder()
    private let continuation: AsyncStream<Event>.Continuation
    /// Events as they arrive. Iterate this to drive the UI.
    public let events: AsyncStream<Event>

    public init(host: String, port: UInt16, pairingToken: String) {
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: TerminalTLS.clientParameters(pairingToken: pairingToken)
        )
        (events, continuation) = AsyncStream.makeStream()
    }

    /// Establishes the encrypted channel. Throws if the TLS handshake fails
    /// (e.g. a token mismatch). Begins delivering ``events`` on success.
    public func connect(timeout: TimeInterval = 10) async throws {
        let once = ResumeOnceClient()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if once.claim() { cont.resume() }
                case .failed(let error):
                    if once.claim() { cont.resume(throwing: error) }
                    self?.finish(exitCode: nil)
                case .cancelled:
                    self?.finish(exitCode: nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                if once.claim() { cont.resume(throwing: TransportError.notConnected) }
            }
        }
        receive()
    }

    /// Sends the auth handshake — the pairing token plus a proof of the master
    /// password. Watch ``events`` for `.authenticated` or `.authFailed`.
    public func authenticate(passwordProof: String, token: String) {
        sendControl(.auth(token: token, passwordProof: passwordProof))
    }

    /// Reattaches to an existing shell session after a reconnect.
    public func attach(sessionID: String) {
        sendControl(.attach(sessionID: sessionID))
    }

    /// Sends keystrokes to the shell.
    public func send(_ data: Data) {
        sendFrame(TerminalFrame(type: .data, payload: data))
    }

    /// Reports a new on-screen terminal size so the pty reflows.
    public func resize(cols: Int, rows: Int) {
        guard let payload = try? MessageCodec.encode(TerminalResize(cols: cols, rows: rows)) else { return }
        sendFrame(TerminalFrame(type: .resize, payload: payload))
    }

    public func close() {
        connection.cancel()
        finish(exitCode: nil)
    }

    // MARK: - internals

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty, let frames = try? self.decoder.append(data) {
                for frame in frames { self.handle(frame) }
            }
            if isComplete || error != nil {
                self.finish(exitCode: nil)
                return
            }
            self.receive()
        }
    }

    private func handle(_ frame: TerminalFrame) {
        switch frame.type {
        case .data:
            continuation.yield(.output(frame.payload))
        case .control:
            guard let control = try? MessageCodec.decode(TerminalServerControl.self, from: frame.payload) else { return }
            switch control {
            case let .authOK(sessionID): continuation.yield(.authenticated(sessionID: sessionID))
            case let .authFailed(reason): continuation.yield(.authFailed(reason))
            case let .sessionEnded(code): finish(exitCode: code)
            }
        case .ping:
            sendFrame(TerminalFrame(type: .pong))
        case .resize, .pong:
            break
        }
    }

    private func sendControl(_ message: TerminalClientControl) {
        guard let payload = try? MessageCodec.encode(message) else { return }
        sendFrame(TerminalFrame(type: .control, payload: payload))
    }

    private func sendFrame(_ frame: TerminalFrame) {
        guard let bytes = try? TerminalFrameCodec.frame(frame) else { return }
        connection.send(content: bytes, completion: .contentProcessed { _ in })
    }

    private var finished = false
    private func finish(exitCode: Int32?) {
        queue.async { [weak self] in
            guard let self, !self.finished else { return }
            self.finished = true
            self.continuation.yield(.ended(exitCode: exitCode))
            self.continuation.finish()
        }
    }
}

private final class ResumeOnceClient: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if fired { return false }; fired = true; return true }
}
