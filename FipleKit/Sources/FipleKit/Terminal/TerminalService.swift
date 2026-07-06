#if os(macOS)
import Foundation
import Network

/// The Mac's privileged terminal listener: a TLS-PSK channel that authenticates
/// with the pairing token + master password, then bridges an encrypted socket to
/// a live `PTYSession`. Separate from the plaintext tile listener (ADR-0005).
///
/// Off by default in the app; the app constructs and `start()`s it only after
/// the user enables the feature and sets a master password.
public final class TerminalService: @unchecked Sendable {
    private let pairingToken: String
    private let passwordRecord: MasterPasswordRecord
    private let shellPath: String?
    private let shellArguments: [String]?
    private let queue = DispatchQueue(label: "com.fiple.terminal.service")
    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: ConnectionSession] = [:]

    public init(
        pairingToken: String,
        passwordRecord: MasterPasswordRecord,
        shellPath: String? = nil,
        shellArguments: [String]? = nil
    ) {
        self.pairingToken = pairingToken
        self.passwordRecord = passwordRecord
        self.shellPath = shellPath
        self.shellArguments = shellArguments
    }

    /// Starts the TLS-PSK listener and returns the bound port.
    @discardableResult
    public func start(port: NWEndpoint.Port = .any) async throws -> UInt16 {
        let params = TerminalTLS.serverParameters(pairingToken: pairingToken)
        let listener = try NWListener(using: params, on: port)
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        self.listener = listener

        return try await withCheckedThrowingContinuation { cont in
            let guardOnce = ResumeOnce()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if guardOnce.claim() { cont.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let error):
                    if guardOnce.claim() { cont.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.start(queue: self.queue)
        }
    }

    public func stop() {
        queue.sync {
            for session in sessions.values { session.close() }
            sessions.removeAll()
            listener?.cancel()
            listener = nil
        }
    }

    private func accept(_ connection: NWConnection) {
        let session = ConnectionSession(
            connection: connection,
            pairingToken: pairingToken,
            passwordRecord: passwordRecord,
            shellPath: shellPath,
            shellArguments: shellArguments,
            queue: queue
        )
        sessions[ObjectIdentifier(session)] = session
        session.onFinished = { [weak self] in
            self?.queue.async { self?.sessions[ObjectIdentifier(session)] = nil }
        }
        session.start()
    }
}

/// One accepted connection: runs the auth handshake, then pipes the encrypted
/// channel to a pty. Owned and confined to the service's serial queue.
private final class ConnectionSession: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var decoder = TerminalFrameDecoder()
    private var authenticator: TerminalAuthenticator
    private let shellPath: String?
    private let shellArguments: [String]?

    private var authenticated = false
    private var pty: PTYSession?
    private var scrollback = ScrollbackBuffer()

    var onFinished: (@Sendable () -> Void)?

    init(
        connection: NWConnection,
        pairingToken: String,
        passwordRecord: MasterPasswordRecord,
        shellPath: String?,
        shellArguments: [String]?,
        queue: DispatchQueue
    ) {
        self.connection = connection
        self.queue = queue
        self.shellPath = shellPath
        self.shellArguments = shellArguments
        self.authenticator = TerminalAuthenticator(
            record: passwordRecord,
            authorizedTokens: [pairingToken]
        )
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.close()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                do {
                    for frame in try self.decoder.append(data) {
                        self.handle(frame)
                    }
                } catch {
                    self.close()
                    return
                }
            }
            if isComplete || error != nil {
                self.close()
                return
            }
            self.receive()
        }
    }

    private func handle(_ frame: TerminalFrame) {
        if !authenticated {
            // Pre-auth, only a CONTROL auth message is meaningful.
            guard frame.type == .control,
                  let control = try? MessageCodec.decode(TerminalClientControl.self, from: frame.payload)
            else { return }
            if case let .auth(token, proof) = control {
                authenticate(token: token, proof: proof)
            }
            return
        }

        switch frame.type {
        case .data:
            pty?.write(frame.payload)
        case .resize:
            if let size = try? MessageCodec.decode(TerminalResize.self, from: frame.payload) {
                pty?.resize(cols: size.cols, rows: size.rows)
            }
        case .ping:
            send(TerminalFrame(type: .pong))
        case .control, .pong:
            break
        }
    }

    private func authenticate(token: String, proof: String) {
        let decision = authenticator.authenticate(
            token: token, passwordProof: proof, now: Date(),
            makeSessionID: { UUID().uuidString }
        )
        switch decision {
        case let .authorized(reply):
            authenticated = true
            sendControl(reply)
            spawnPTY()
        case let .rejected(reason):
            // Send the rejection, then drop the socket only once the bytes have
            // flushed — cancelling first would swallow the frame.
            if let payload = try? MessageCodec.encode(TerminalServerControl.authFailed(reason: reason)),
               let bytes = try? TerminalFrameCodec.frame(TerminalFrame(type: .control, payload: payload)) {
                connection.send(content: bytes, completion: .contentProcessed { [weak self] _ in
                    self?.queue.async { self?.close() }
                })
            } else {
                close()
            }
        }
    }

    private func spawnPTY() {
        do {
            let pty = try PTYSession(shellPath: shellPath, arguments: shellArguments)
            pty.onOutput = { [weak self] out in
                guard let self else { return }
                self.queue.async {
                    self.scrollback.append(out)
                    self.send(TerminalFrame(type: .data, payload: out))
                }
            }
            pty.onExit = { [weak self] code in
                guard let self else { return }
                self.queue.async {
                    self.sendControl(.sessionEnded(exitCode: code))
                    self.close()
                }
            }
            self.pty = pty
        } catch {
            sendControl(.sessionEnded(exitCode: nil))
            close()
        }
    }

    private func sendControl(_ message: TerminalServerControl) {
        guard let payload = try? MessageCodec.encode(message) else { return }
        send(TerminalFrame(type: .control, payload: payload))
    }

    private func send(_ frame: TerminalFrame) {
        guard let bytes = try? TerminalFrameCodec.frame(frame) else { return }
        connection.send(content: bytes, completion: .contentProcessed { _ in })
    }

    private var closed = false
    func close() {
        if closed { return }
        closed = true
        pty?.close()
        pty = nil
        connection.cancel()
        onFinished?()
    }
}

/// One-shot latch so a continuation resumes exactly once across concurrent
/// Network.framework callbacks.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}
#endif
