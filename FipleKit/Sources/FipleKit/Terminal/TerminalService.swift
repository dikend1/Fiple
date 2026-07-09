#if os(macOS)
import Foundation
import Network

/// The Mac's privileged terminal listener: a TLS-PSK channel that authenticates
/// with the pairing token + master password, then bridges an encrypted socket to
/// a live shell session. Separate from the plaintext tile listener (ADR-0005).
///
/// Shell sessions live in a registry independent of connections, so a phone that
/// backgrounds and reconnects resumes the same shell (detach/reattach). Off by
/// default in the app; started only after the user enables the feature and sets
/// a master password.
public final class TerminalService: @unchecked Sendable {
    private let pairingToken: String
    private let passwordRecord: MasterPasswordRecord
    private let queue = DispatchQueue(label: "com.fiple.terminal.service")
    private let registry: TerminalSessionRegistry
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: ConnectionSession] = [:]
    private var activeCount = 0

    /// Reports how many phones are currently authenticated to the terminal, so
    /// the Mac UI can show "iPhone connected" instead of a raw port. Fired on the
    /// service queue whenever the count changes.
    public var onActiveSessionsChanged: (@Sendable (Int) -> Void)?

    /// - Parameter graceInterval: how long a disconnected shell survives before
    ///   SIGHUP (default 10 minutes).
    public init(
        pairingToken: String,
        passwordRecord: MasterPasswordRecord,
        shellPath: String? = nil,
        shellArguments: [String]? = nil,
        graceInterval: TimeInterval = 600
    ) {
        self.pairingToken = pairingToken
        self.passwordRecord = passwordRecord
        self.registry = TerminalSessionRegistry(
            queue: queue, graceInterval: graceInterval,
            shellPath: shellPath, shellArguments: shellArguments
        )
    }

    /// The port the listener bound to, so a rebind (after sleep / an interface
    /// change) reuses it and the phone's saved target stays valid.
    private var boundPort: UInt16 = 0

    /// Starts the TLS-PSK listener and returns the bound port.
    @discardableResult
    public func start(port: NWEndpoint.Port = .any) async throws -> UInt16 {
        let listener = try makeListener(on: port)
        self.listener = listener

        let bound: UInt16 = try await withCheckedThrowingContinuation { cont in
            let guardOnce = ResumeOnce()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if guardOnce.claim() { cont.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let error):
                    if guardOnce.claim() { cont.resume(throwing: error) }
                    else { self?.rebind() } // failed after start — recover
                default:
                    break
                }
            }
            listener.start(queue: self.queue)
        }
        boundPort = bound
        return bound
    }

    private func makeListener(on port: NWEndpoint.Port) throws -> NWListener {
        let params = TerminalTLS.serverParameters(pairingToken: pairingToken)
        let listener = try NWListener(using: params, on: port)
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        return listener
    }

    /// Rebuilds the listener on the same port after it dies (Mac wake, Wi-Fi
    /// change) without touching the session registry — so detached shells that
    /// survived the interruption can still be resumed. Best-effort.
    private func rebind() {
        guard boundPort != 0, let reusePort = NWEndpoint.Port(rawValue: boundPort) else { return }
        listener?.cancel()
        guard let listener = try? makeListener(on: reusePort) else { return }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.rebind() }
        }
        listener.start(queue: queue)
    }

    public func stop() {
        queue.sync {
            for connection in connections.values { connection.teardown() }
            connections.removeAll()
            registry.closeAll()
            listener?.cancel()
            listener = nil
        }
    }

    private func accept(_ connection: NWConnection) {
        let session = ConnectionSession(
            connection: connection,
            pairingToken: pairingToken,
            passwordRecord: passwordRecord,
            registry: registry,
            queue: queue
        )
        connections[ObjectIdentifier(session)] = session
        session.onFinished = { [weak self] in
            guard let self else { return }
            self.queue.async { self.connections[ObjectIdentifier(session)] = nil }
        }
        session.onActiveChange = { [weak self] delta in
            guard let self else { return }
            self.queue.async { self.updateActiveCount(by: delta) }
        }
        session.start()
    }

    private func updateActiveCount(by delta: Int) {
        activeCount = max(0, activeCount + delta)
        onActiveSessionsChanged?(activeCount)
    }
}

/// One accepted connection: runs the auth handshake, then bridges the encrypted
/// channel to a `ShellSession` (new or resumed). Confined to the service queue.
private final class ConnectionSession: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let registry: TerminalSessionRegistry
    private var decoder = TerminalFrameDecoder()
    private var authenticator: TerminalAuthenticator

    private var authenticated = false
    /// The shell this connection is currently driving (nil until authorized).
    private weak var shell: ShellSession?

    var onFinished: (@Sendable () -> Void)?
    /// +1 when this connection authenticates, -1 when it drops (once each).
    var onActiveChange: (@Sendable (Int) -> Void)?
    private var countedActive = false

    init(
        connection: NWConnection,
        pairingToken: String,
        passwordRecord: MasterPasswordRecord,
        registry: TerminalSessionRegistry,
        queue: DispatchQueue
    ) {
        self.connection = connection
        self.queue = queue
        self.registry = registry
        self.authenticator = TerminalAuthenticator(
            record: passwordRecord,
            authorizedTokens: [pairingToken]
        )
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                guard let self else { return }
                self.queue.async { self.finish() }
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
                    for frame in try self.decoder.append(data) { self.handle(frame) }
                } catch {
                    self.finish()
                    return
                }
            }
            if isComplete || error != nil {
                self.finish()
                return
            }
            self.receive()
        }
    }

    private func handle(_ frame: TerminalFrame) {
        if !authenticated {
            guard frame.type == .control,
                  let control = try? MessageCodec.decode(TerminalClientControl.self, from: frame.payload)
            else { return }
            if case let .auth(token, proof, resumeSessionID, resumeOnly) = control {
                authenticate(token: token, proof: proof, resumeSessionID: resumeSessionID, resumeOnly: resumeOnly)
            }
            return
        }

        switch frame.type {
        case .data:
            shell?.write(frame.payload)
        case .resize:
            if let size = try? MessageCodec.decode(TerminalResize.self, from: frame.payload) {
                shell?.resize(cols: size.cols, rows: size.rows)
            }
        case .ping:
            send(TerminalFrame(type: .pong))
        case .control:
            // Post-auth control: the phone closing one of its session tabs.
            // Unknown control types from a newer phone are skipped, not fatal.
            guard let control = try? MessageCodec.decodeIfKnown(TerminalClientControl.self, from: frame.payload)
            else { return }
            if case let .endSession(sessionID) = control {
                if shell?.id == sessionID { shell = nil }
                registry.end(id: sessionID)
            }
        case .pong:
            break
        }
    }

    private func authenticate(token: String, proof: String, resumeSessionID: String?, resumeOnly: Bool) {
        switch authenticator.authenticate(token: token, passwordProof: proof, now: Date()) {
        case .authorized:
            authenticated = true
            attachShell(resumeSessionID: resumeSessionID, resumeOnly: resumeOnly)
        case let .rejected(reason):
            // Send the rejection, then drop the socket only once it has flushed.
            if let payload = try? MessageCodec.encode(TerminalServerControl.authFailed(reason: reason)),
               let bytes = try? TerminalFrameCodec.frame(TerminalFrame(type: .control, payload: payload)) {
                connection.send(content: bytes, completion: .contentProcessed { [weak self] _ in
                    guard let self else { return }
                    self.queue.async { self.finish() }
                })
            } else {
                finish()
            }
        }
    }

    private func attachShell(resumeSessionID: String?, resumeOnly: Bool = false) {
        // Resume the named session if it's still alive; otherwise start fresh.
        let session: ShellSession
        if let id = resumeSessionID, let existing = registry.session(id: id) {
            session = existing
        } else if resumeOnly {
            // A strict restore of a shell that's gone: report it ended rather
            // than silently handing back a fresh shell the user didn't ask for.
            sendControl(.sessionEnded(exitCode: nil))
            finish()
            return
        } else {
            do {
                session = try registry.create()
            } catch {
                sendControl(.sessionEnded(exitCode: nil))
                finish()
                return
            }
        }
        shell = session
        if !countedActive { countedActive = true; onActiveChange?(1) }
        sendControl(.authOK(sessionID: session.id))
        // Attach after replying so the phone has the id before buffered bytes.
        session.attach(sink: { [weak self] frame in self?.send(frame) })
    }

    private func sendControl(_ message: TerminalServerControl) {
        guard let payload = try? MessageCodec.encode(message) else { return }
        send(TerminalFrame(type: .control, payload: payload))
    }

    private func send(_ frame: TerminalFrame) {
        guard let bytes = try? TerminalFrameCodec.frame(frame) else { return }
        connection.send(content: bytes, completion: .contentProcessed { _ in })
    }

    private var finished = false
    /// The phone dropped: detach the shell (starting its grace period) and free
    /// the connection. The shell keeps running so a reconnect can resume it.
    func finish() {
        if finished { return }
        finished = true
        if countedActive { countedActive = false; onActiveChange?(-1) }
        shell?.detach()
        shell = nil
        connection.cancel()
        onFinished?()
    }

    /// Hard teardown when the whole service stops (does not preserve the shell —
    /// the registry closes it separately).
    func teardown() {
        finished = true
        connection.cancel()
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
