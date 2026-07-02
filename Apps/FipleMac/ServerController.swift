import AppKit
import FipleKit
import Foundation
import Observation

/// Drives the Mac side: advertises over the LAN, performs the code handshake,
/// pushes tile snapshots, and runs triggered tiles. MVP keeps a single active
/// pairing — one connected phone at a time.
@MainActor
@Observable
final class ServerController {
    enum Status: Equatable {
        case idle, advertising, connected
    }

    private(set) var status: Status = .idle
    private(set) var pairingCode: PairingCode?
    private(set) var lastRun: RunResult?

    /// Called after a tile is run, so launch history can be recorded without the
    /// transport layer depending on the Recent store.
    @ObservationIgnored var didRun: (@MainActor (Tile) -> Void)?
    /// Called after a single Fiple Bar action is run, so it lands in history too.
    @ObservationIgnored var didRunAction: (@MainActor (Action) -> Void)?

    let macName = Host.current().localizedName ?? "Mac"
    let macID: String = ServerController.stableMacID()

    @ObservationIgnored let store: TileStore
    @ObservationIgnored let pinned: PinnedAppsStore
    @ObservationIgnored private let server = FipleServer()
    @ObservationIgnored private let executor = MacActionExecutor()
    @ObservationIgnored private var peer: PeerConnection?
    @ObservationIgnored private var isPaired = false
    @ObservationIgnored private var acceptTask: Task<Void, Never>?
    @ObservationIgnored private var failureWatchTask: Task<Void, Never>?
    @ObservationIgnored private var connectionTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?

    /// Persistent token for the currently remembered phone. Survives Mac app
    /// restarts so a known phone reconnects silently; cleared on explicit
    /// disconnect, which forces a fresh code. Stored in the Keychain, not
    /// UserDefaults (a bearer credential granting remote control).
    @ObservationIgnored private var sessionToken: String?

    /// Brute-force protection for the 4-digit code, shared across every socket
    /// in this advertising session. Reset only on a successful pair or an
    /// explicit restart — never when a connection drops.
    @ObservationIgnored private var throttle = PairingThrottle()

    init(store: TileStore, pinned: PinnedAppsStore) {
        self.store = store
        self.pinned = pinned
        sessionToken = Self.loadToken()
        store.didChange = { [weak self] in
            Task { await self?.pushSnapshot() }
        }
        pinned.didChange = { [weak self] in
            Task { await self?.pushFipleBar() }
        }
    }

    /// Idempotent: starts advertising and accepting connections.
    func start() async {
        guard status == .idle else { return }
        throttle.reset()
        regenerateCode()
        do {
            _ = try await server.start(deviceName: macName)
            status = .advertising
            FipleLog.pairing.info("advertising started — code \(pairingCode?.value ?? "?")")
        } catch {
            FipleLog.pairing.error("failed to start server: \(error.localizedDescription)")
            status = .idle
            return
        }
        acceptTask?.cancel()
        acceptTask = Task { [weak self] in
            guard let self else { return }
            for await peer in await self.server.newConnections {
                // Handle each connection in its own task. If we `await handle`
                // here, the accept loop blocks inside the message loop until that
                // connection closes — so a phone that relaunches (its old TCP
                // socket not yet torn down on our side) never gets served: the
                // new connection sits unhandled and the phone hangs on
                // "Connecting…". Spawning a task lets us accept it immediately.
                self.track(peer)
            }
        }
        watchForListenerFailure()
        observeWake()
    }

    /// Runs a connection's message loop in a tracked task so it can be
    /// cancelled on teardown instead of living detached forever.
    private func track(_ peer: PeerConnection) {
        let key = ObjectIdentifier(peer)
        connectionTasks[key] = Task { [weak self] in
            await self?.handle(peer)
            self?.connectionTasks[key] = nil
        }
    }

    /// A listener that dies after start (interface change, network reset) would
    /// otherwise leave the UI claiming "advertising" over a dead socket.
    private func watchForListenerFailure() {
        guard failureWatchTask == nil else { return }
        failureWatchTask = Task { [weak self] in
            guard let self else { return }
            for await _ in await self.server.listenerFailures {
                FipleLog.discovery.notice("listener died — restarting advertising")
                await self.restartAdvertising()
            }
        }
    }

    /// Bonjour advertising often doesn't come back by itself after sleep, so
    /// re-assert it on wake. Established peer connections are untouched.
    private func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.restartAdvertising() }
        }
    }

    private func restartAdvertising() async {
        guard status != .idle else { return } // never started; nothing to restore
        do {
            _ = try await server.start(deviceName: macName)
            status = (peer != nil && isPaired) ? .connected : .advertising
            FipleLog.discovery.info("advertising restored")
        } catch {
            FipleLog.discovery.error("failed to restore advertising: \(error.localizedDescription)")
        }
    }

    /// Explicit disconnect: invalidates the remembered pairing so the next
    /// connection requires a fresh code (PRD `fiple-pairing`).
    func disconnect() async {
        FipleLog.pairing.info("explicit disconnect — clearing remembered pairing")
        if let peer { await peer.close() }
        peer = nil
        isPaired = false
        sessionToken = nil
        Keychain.remove(Self.tokenKey)
        throttle.reset()
        status = .advertising
        regenerateCode()
    }

    // MARK: - Connection handling

    private func handle(_ peer: PeerConnection) async {
        // Do NOT evict the currently-paired phone here: an unauthenticated socket
        // must never be able to kick the connected phone or clear `isPaired` just
        // by opening a TCP connection. The new connection becomes the active peer
        // only once it actually authenticates — the supersede happens in
        // `acceptPairing`. Until then it runs on its own auth timeout and cannot
        // run actions (gated on `peer === self.peer` in `process`).
        // Reap the connection if it never authenticates (pair/reconnect) in time.
        await peer.startAuthTimeout(.seconds(Self.authTimeoutSeconds))
        do {
            for try await payload in await peer.messages {
                // A newer phone may send message types this build doesn't know;
                // skipping them keeps the session alive instead of tearing it
                // down (and looping: reconnect → same message → drop again).
                guard let message = try MessageCodec.decodeIfKnown(ClientMessage.self, from: payload) else {
                    FipleLog.connection.notice("skipping unknown message type from peer")
                    continue
                }
                await process(message, on: peer)
            }
        } catch {
            FipleLog.connection.notice("peer stream ended: \(error.localizedDescription)")
            // A malformed payload of a known type is fatal for this session.
            // Close explicitly — otherwise the socket stays open and the phone
            // keeps talking to a Mac that stopped listening.
            await peer.close()
        }
        if self.peer === peer { resetToAdvertising() }
    }

    private func process(_ message: ClientMessage, on peer: PeerConnection) async {
        switch message {
        case let .pair(code):
            let matches = pairingCode.map { $0.value == code } ?? false
            switch throttle.register(matches: matches, now: Date()) {
            case .accepted:
                FipleLog.pairing.info("pair accepted — code matched")
                // Fresh code pairing: mint a new token so any previously leaked
                // token is invalidated and a different phone never inherits one.
                await acceptPairing(on: peer, rotateToken: true)
            case let .rejected(remaining):
                FipleLog.pairing.notice("pair rejected — wrong code (\(remaining) attempt(s) left)")
                try? await peer.send(ServerMessage.pairRejected(reason: .incorrectCode))
            case .lockedOut:
                // Limit hit: rotate the code (every prior guess is now worthless,
                // and the new code shows in the UI), tell the phone, drop the socket.
                regenerateCode()
                FipleLog.pairing.error("too many attempts — locked out \(Int(throttle.lockoutDuration))s, code rotated")
                try? await peer.send(ServerMessage.pairRejected(reason: .tooManyAttempts))
                await peer.close()
            case .ignored:
                FipleLog.pairing.notice("pair attempt ignored — still locked out")
                try? await peer.send(ServerMessage.pairRejected(reason: .tooManyAttempts))
                await peer.close()
            }

        case let .reconnect(token):
            if let saved = sessionToken, Self.constantTimeEquals(token, saved) {
                FipleLog.pairing.info("reconnect accepted — token matched")
                // Known phone reconnecting: keep its existing token.
                await acceptPairing(on: peer, rotateToken: false)
            } else {
                FipleLog.pairing.notice("reconnect rejected — token expired")
                try? await peer.send(ServerMessage.pairRejected(reason: .pairingExpired))
            }

        case let .run(tileID):
            guard peer === self.peer, isPaired else {
                FipleLog.execution.notice("run ignored — not the authenticated peer")
                return
            }
            guard let tile = store.tiles.first(where: { $0.id == tileID }) else {
                // A tile deleted between snapshots: report a failure so the
                // phone clears its spinner instead of waiting forever.
                FipleLog.execution.notice("run rejected — unknown tile id")
                let rejected = RunResult(tileID: tileID, actions: [.failure(tileID, "This workspace no longer exists on the Mac")])
                lastRun = rejected
                try? await peer.send(ServerMessage.runResult(rejected))
                return
            }
            let result = await TileRunner(executor: executor).run(tile)
            lastRun = result
            didRun?(tile)
            try? await peer.send(ServerMessage.runResult(result))

        case let .runAction(actionID):
            guard peer === self.peer, isPaired else {
                FipleLog.execution.notice("runAction ignored — not the authenticated peer")
                return
            }
            // Never execute a client-supplied action. Resolve the id against the
            // Mac's own saved Fiple Bar / tiles and run only what actually exists
            // here — so launchApp/openURL payloads are always ours.
            guard let action = ActionLookup.resolve(actionID, fipleBar: pinned.actions, tiles: store.tiles) else {
                FipleLog.execution.error("runAction rejected — unknown action id")
                // Still report a failure so the phone clears its spinner.
                let rejected = RunResult(tileID: actionID, actions: [.failure(actionID, "Action not available on this Mac")])
                lastRun = rejected
                try? await peer.send(ServerMessage.runResult(rejected))
                return
            }
            let actionResult = await executor.execute(action)
            // Report under the action's own id so the phone can clear its spinner.
            let result = RunResult(tileID: action.id, actions: [actionResult])
            lastRun = result
            didRunAction?(action)
            try? await peer.send(ServerMessage.runResult(result))
        }
    }

    private func acceptPairing(on peer: PeerConnection, rotateToken: Bool) async {
        // This connection has now proven itself, so it supersedes the previous
        // peer (MVP: a single phone). Closing the stale socket here — rather than
        // on raw connect — means an unauthenticated peer can never evict the
        // connected phone.
        if let old = self.peer, old !== peer {
            FipleLog.connection.info("superseding previous connection")
            await old.close()
        }
        self.peer = peer
        await peer.markAuthenticated()
        isPaired = true
        status = .connected
        FipleLog.pairing.info("paired — sending tiles snapshot")
        // Fresh code pairing mints a new token (invalidating any prior one);
        // a token reconnect keeps the credential it just presented.
        let token = rotateToken ? UUID().uuidString : (sessionToken ?? UUID().uuidString)
        sessionToken = token
        Keychain.set(token, for: Self.tokenKey)
        try? await peer.send(ServerMessage.paired(macID: macID, macName: macName, token: token))
        // Follow the pairing ack with the hardware family so the remote shows
        // the right device icon. Older remotes skip this unknown message type.
        try? await peer.send(ServerMessage.deviceInfo(macKind: MacDeviceInfo.current))
        await sendTilesSnapshot(to: peer)
        await sendFipleBar(to: peer)
    }

    /// Compares bearer tokens without early exit, so a mismatch's timing leaks
    /// nothing about how many leading characters were right.
    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let lhs = Array(a.utf8), rhs = Array(b.utf8)
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for i in lhs.indices { diff |= lhs[i] ^ rhs[i] }
        return diff == 0
    }

    /// Run a tile locally from the Mac (one-click preset launch). Recorded in
    /// history exactly like a phone-triggered run.
    func run(_ tile: Tile) async {
        let result = await TileRunner(executor: executor).run(tile)
        lastRun = result
        didRun?(tile)
    }

    /// Run a single action locally from the Mac (used to relaunch an item from
    /// Recent). Recorded in history like a Fiple Bar action launch.
    func run(_ action: Action) async {
        let actionResult = await executor.execute(action)
        lastRun = RunResult(tileID: action.id, actions: [actionResult])
        didRunAction?(action)
    }

    private func pushSnapshot() async {
        guard isPaired, let peer else { return }
        await sendTilesSnapshot(to: peer)
    }

    private func pushFipleBar() async {
        guard isPaired, let peer else { return }
        await sendFipleBar(to: peer)
    }

    /// Snapshots carry PNG icons, so enough tiles can outgrow the frame cap.
    /// The receiver would kill the connection and reconnect — which resends the
    /// same snapshot, forever. Better a snapshot without icons than no session.
    private func sendTilesSnapshot(to peer: PeerConnection) async {
        var tiles = snapshotTiles()
        if exceedsFrameLimit(ServerMessage.tilesSnapshot(tiles: tiles)) {
            FipleLog.connection.notice("tiles snapshot over frame limit — sending without icons")
            tiles = tiles.map { tile in
                var tile = tile
                tile.actions = tile.actions.map { var a = $0; a.iconImageData = nil; return a }
                return tile
            }
        }
        try? await peer.send(ServerMessage.tilesSnapshot(tiles: tiles))
    }

    private func sendFipleBar(to peer: PeerConnection) async {
        var actions = snapshotFipleBar()
        if exceedsFrameLimit(ServerMessage.fipleBar(actions: actions)) {
            FipleLog.connection.notice("fiple bar over frame limit — sending without icons")
            actions = actions.map { var a = $0; a.iconImageData = nil; return a }
        }
        try? await peer.send(ServerMessage.fipleBar(actions: actions))
    }

    private func exceedsFrameLimit(_ message: ServerMessage) -> Bool {
        guard let data = try? MessageCodec.encode(message) else { return false }
        return data.count > FrameCodec.maxFrameSize
    }

    /// Enriches an outgoing action with the data only the Mac can resolve: the
    /// app's real icon (PNG) and its real display name. Both live only on the
    /// Mac (the phone can't produce an app icon, and deriving a name from a
    /// bundle id yields junk), so we attach them just before sending. Website and
    /// shortcut actions keep a nil icon — the phone draws a favicon / SF Symbol.
    private func resolved(_ action: Action) -> Action {
        var action = action
        if action.iconImageData == nil {
            action.iconImageData = SystemIcon.pngData(for: action.kind)
        }
        if action.displayName == nil, case let .launchApp(bundleID) = action.kind {
            action.displayName = SystemIcon.appDisplayName(bundleID: bundleID)
        }
        return action
    }

    private func snapshotFipleBar() -> [Action] {
        pinned.actions.map(resolved)
    }

    private func snapshotTiles() -> [Tile] {
        store.tiles.map { tile in
            var tile = tile
            tile.actions = tile.actions.map(resolved)
            return tile
        }
    }

    // MARK: - State

    /// Transient drop (Wi-Fi blip): keep the code and token so a remembered
    /// phone reconnects silently.
    private func resetToAdvertising() {
        FipleLog.connection.info("peer dropped — back to advertising (pairing remembered)")
        peer = nil
        isPaired = false
        status = .advertising
    }

    private func regenerateCode() {
        pairingCode = PairingCode.random()
    }

    /// How long an inbound connection may stay open without authenticating.
    private static let authTimeoutSeconds = 15

    private static let tokenKey = "com.fiple.sessionToken"

    /// Loads the session token from the Keychain, migrating a token left in
    /// UserDefaults by an earlier build (then scrubbing the plaintext copy).
    private static func loadToken() -> String? {
        // Drop any token left in the legacy keychain by an older build. We never
        // read it (that would trigger the "enter the login keychain password"
        // prompt); re-pairing recreates it in the data-protection keychain.
        Keychain.purgeLegacy(tokenKey)
        if let token = Keychain.get(tokenKey) { return token }
        if let legacy = UserDefaults.standard.string(forKey: tokenKey) {
            // Only scrub the plaintext copy once it is safely in the Keychain.
            if Keychain.set(legacy, for: tokenKey) {
                UserDefaults.standard.removeObject(forKey: tokenKey)
            }
            return legacy
        }
        return nil
    }

    /// A stable identifier for this Mac, persisted in UserDefaults.
    private static func stableMacID() -> String {
        let key = "com.fiple.macID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}
