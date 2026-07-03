import FipleKit
import Foundation
import Network
import Observation

/// Drives the iPhone remote: silent discovery, code/token authentication,
/// rendering the Mac's tiles, and triggering them. Pure remote — never edits.
@MainActor
@Observable
final class RemoteController {
    enum Phase: Equatable {
        case searching     // looking for a Mac on the LAN
        case readyToPair   // Mac found, awaiting code
        case connecting    // handshake in flight
        case connected     // paired, tiles available
    }

    private(set) var phase: Phase = .searching
    /// Whether this phone has paired with a Mac before (a reconnect token is
    /// stored). Keeps the tabbed UI — and off-LAN Files access — available when
    /// away from the Mac's network, instead of falling back to first-run pairing.
    var hasEverPaired: Bool { storedToken != nil }
    private(set) var macName: String?
    /// The connected Mac's hardware family, reported by the Mac so the connection
    /// card shows the right device icon. Defaults to `.laptop` (the common case,
    /// and what an older Mac that doesn't report it implies).
    private(set) var macKind: MacKind = .laptop
    private(set) var tiles: [Tile] = []
    private(set) var pairError: String?
    private(set) var runningTileID: UUID?
    private(set) var runningActionID: UUID?
    /// A user-visible launch failure (the Mac reported it, the send failed, or
    /// the Mac never confirmed). The UI shows it transiently and dismisses it.
    private(set) var runFailureMessage: String?
    /// Set by UI (e.g. "Pair New Mac" in Settings) to force the pairing sheet
    /// open even in phases where it wouldn't auto-present. Consumed by RootView.
    var pairingRequested = false
    /// The Mac's curated Fiple Bar — quick actions synced from the Mac (apps,
    /// websites, files), tapped here to launch on the Mac.
    private(set) var fipleBar: [Action] = []
    /// Phone-side launch history. The Mac keeps its own `RecentStore`, but it is
    /// not sent over the wire, so the remote records what *it* triggers — newest
    /// first, capped and persisted so it survives relaunch.
    private(set) var recents: [LaunchRecord] = []

    /// Workspaces are multi-action tiles; single-action tiles are "quick access".
    var workspaces: [Tile] { tiles.filter(\.isWorkspace) }

    /// Every individual action across all tiles, de-duplicated — the Quick
    /// Access row. Mirrors the Mac's action catalogue, derived from the same
    /// tile snapshot.
    var quickAccess: [QuickAction] {
        var seen = Set<String>()
        var result: [QuickAction] = []
        for tile in tiles {
            for action in tile.actions {
                let item = QuickAction(action: action, tileID: tile.id)
                if seen.insert(item.dedupeKey).inserted { result.append(item) }
            }
        }
        return result
    }

    @ObservationIgnored private let client = FipleClient()
    @ObservationIgnored private var peer: PeerConnection?
    @ObservationIgnored private var endpoint: NWEndpoint?
    @ObservationIgnored private var discoverTask: Task<Void, Never>?
    @ObservationIgnored private var receiveTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    /// Whether the in-flight handshake presented a stored token (vs a fresh
    /// code). Only a token reconnect verifies the Mac's identity — a fresh code
    /// pair legitimately targets a new Mac.
    @ObservationIgnored private var pendingAuthIsReconnect = false

    /// When each in-flight tile/action was triggered, so we can log the
    /// round-trip latency (tap → Mac confirms) when the result returns. This is
    /// the number to watch for "does it feel instant?" — aim for < ~150 ms.
    @ObservationIgnored private var runStartedAt: [UUID: Date] = [:]

    // MARK: - Lifecycle

    func begin() {
        guard discoverTask == nil else { return }
        migrateLegacyToken()
        recents = LaunchRecord.load()
        #if DEBUG
        // Offline demo mode (`-demo` launch arg / SwiftUI previews): skip discovery
        // and present the connected UI on fixture tiles, so the screens can be
        // exercised without a paired Mac. Debug builds only.
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            loadDemoFixture()
            return
        }
        #endif
        phase = .searching
        startDiscovery()
    }

    private func startDiscovery() {
        discoverTask?.cancel()
        discoverTask = Task { [weak self] in
            guard let self else { return }
            for await endpoint in await self.client.discover() {
                await self.found(endpoint)
            }
        }
    }

    /// Forgets the pinned endpoint and re-browses. Used when the remembered
    /// address stops answering — the Mac may be back under a new address, which
    /// discovery only re-emits on a fresh browse.
    private func restartDiscovery() {
        endpoint = nil
        startDiscovery()
    }

    /// UI entry point for explicitly opening the pairing flow (Settings, or a
    /// first run where no Mac has been found yet).
    func requestPairing() {
        pairingRequested = true
    }

    /// A code the user typed while we were still searching. We hold it and pair
    /// automatically the instant a Mac appears, so they never have to re-enter it.
    @ObservationIgnored private var pendingCode: PairingCode?

    private func found(_ endpoint: NWEndpoint) async {
        guard self.endpoint == nil else { return } // MVP: first Mac wins
        self.endpoint = endpoint
        FipleLog.discovery.info("Mac found on LAN")
        if let token = storedToken {
            FipleLog.pairing.info("auto-reconnecting with stored token")
            await authenticate(.reconnect(token: token), silent: true)
        } else if let pending = pendingCode {
            pendingCode = nil
            await authenticate(.pair(code: pending.value))
        } else {
            phase = .readyToPair
        }
    }

    // MARK: - Pairing

    func submitCode(_ code: String) async {
        guard let parsed = PairingCode(code) else {
            pairError = "Enter the 4-digit code shown on your Mac"
            return
        }
        // No Mac on the LAN yet — remember the code and pair as soon as one shows up.
        guard endpoint != nil else {
            pendingCode = parsed
            pairError = nil
            return
        }
        await authenticate(.pair(code: parsed.value))
    }

    /// `silent` marks background auto-reconnect attempts: their failures must
    /// not bounce the UI into the pairing flow or surface an error — the phone
    /// may simply be off the Mac's network, which the tabbed UI already handles.
    private func authenticate(_ auth: ClientMessage, silent: Bool = false) async {
        guard let endpoint else { return }
        if case .reconnect = auth { pendingAuthIsReconnect = true } else { pendingAuthIsReconnect = false }
        phase = .connecting
        pairError = nil
        do {
            let peer = try await client.connect(to: endpoint)
            self.peer = peer
            startReceiving(on: peer)
            try await peer.send(auth)
        } catch {
            FipleLog.pairing.error("authenticate failed: \(error.localizedDescription)")
            if silent {
                phase = .searching
            } else {
                pairError = "Couldn't reach your Mac"
                phase = .readyToPair
            }
        }
    }

    private func startReceiving(on peer: PeerConnection) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await payload in await peer.messages {
                    // A newer Mac may send message types this build doesn't
                    // know; skip them instead of dropping the session (which
                    // would reconnect into the same message forever).
                    guard let message = try MessageCodec.decodeIfKnown(ServerMessage.self, from: payload) else {
                        FipleLog.connection.notice("skipping unknown message type from Mac")
                        continue
                    }
                    await self.handle(message)
                }
            } catch {
                // fall through to disconnect handling
            }
            await self.handleDrop(peer)
        }
    }

    private func handle(_ message: ServerMessage) async {
        switch message {
        case let .paired(macID, macName, token):
            // On a token reconnect the responder must be the Mac we remember.
            // Anyone can advertise `_fiple._tcp`; without this check a spoofed
            // "paired" reply would be accepted silently after we've already
            // sent the bearer token. Drop the pairing entirely so the token
            // (now potentially exposed) stops being valid grounds for trust.
            if pendingAuthIsReconnect, let expected = storedMacID, expected != macID {
                FipleLog.pairing.error("paired reply from an unexpected Mac — clearing pairing")
                storedToken = nil
                storedMacID = nil
                await peer?.close()
                peer = nil
                pairError = "This isn't the Mac you paired with. Enter the code shown on your Mac."
                phase = .readyToPair
                return
            }
            FipleLog.pairing.info("paired with '\(macName)'")
            reconnectTask?.cancel()
            reconnectTask = nil
            self.macName = macName
            storedToken = token
            storedMacID = macID
            pairError = nil
            phase = .connected

        case let .deviceInfo(kind):
            macKind = kind

        case let .pairRejected(reason):
            // a rejected reconnect means the remembered pairing is stale
            FipleLog.pairing.notice("pair rejected: \(reason.rawValue)")
            storedToken = nil
            await peer?.close()
            peer = nil
            pairError = Self.message(for: reason)
            phase = .readyToPair

        case let .tilesSnapshot(tiles):
            FipleLog.pairing.debug("received \(tiles.count) tile(s)")
            self.tiles = tiles.sorted { $0.order < $1.order }

        case let .fipleBar(actions):
            self.fipleBar = actions

        case let .runResult(result):
            if let started = runStartedAt.removeValue(forKey: result.tileID) {
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                FipleLog.execution.info("round-trip \(ms)ms — \(result.actions.allSatisfy(\.ok) ? "ok" : "had failures")")
            }
            if runningTileID == result.tileID { runningTileID = nil }
            if runningActionID == result.tileID { runningActionID = nil }
            // A launch that failed on the Mac looks like success from the couch
            // unless we say something.
            if !result.actions.allSatisfy(\.ok) {
                let name = tiles.first { $0.id == result.tileID }?.name
                    ?? fipleBar.first { $0.id == result.tileID }?.displayLabel
                runFailureMessage = name.map { "Couldn't launch “\($0)” on your Mac" }
                    ?? "Something didn't launch on your Mac"
            }
        }
    }

    // MARK: - Triggering

    func run(_ tile: Tile) async {
        guard phase == .connected, let peer else { return }
        FipleLog.execution.info("triggering tile '\(tile.name)'")
        runningTileID = tile.id
        runStartedAt[tile.id] = Date()
        recordLaunch(of: tile)
        do {
            try await peer.send(ClientMessage.run(tileID: tile.id))
            startRunTimeout(for: tile.id)
        } catch {
            FipleLog.execution.error("run send failed: \(error.localizedDescription)")
            clearRunState(for: tile.id)
            runFailureMessage = "Couldn't reach your Mac — “\(tile.name)” wasn't launched"
        }
    }

    /// Trigger a single Fiple Bar action on the Mac.
    func runAction(_ action: Action) async {
        guard phase == .connected, let peer else { return }
        FipleLog.execution.info("triggering action: \(action.displayLabel)")
        runningActionID = action.id
        runStartedAt[action.id] = Date()
        recordLaunch(of: action)
        // Send only the id; the Mac resolves and runs it from its own Fiple Bar.
        do {
            try await peer.send(ClientMessage.runAction(actionID: action.id))
            startRunTimeout(for: action.id)
        } catch {
            FipleLog.execution.error("runAction send failed: \(error.localizedDescription)")
            clearRunState(for: action.id)
            runFailureMessage = "Couldn't reach your Mac — “\(action.displayLabel)” wasn't launched"
        }
    }

    /// The Mac normally answers in well under a second; if nothing comes back,
    /// stop the spinner and say so instead of letting it spin forever (dropped
    /// result, Mac asleep, tile deleted on an old build that never replies).
    private func startRunTimeout(for id: UUID) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.runTimeoutSeconds))
            guard let self, self.runStartedAt[id] != nil else { return }
            FipleLog.execution.notice("run timed out — no result from the Mac")
            self.clearRunState(for: id)
            self.runFailureMessage = "The Mac didn't confirm the launch"
        }
    }

    private func clearRunState(for id: UUID) {
        runStartedAt[id] = nil
        if runningTileID == id { runningTileID = nil }
        if runningActionID == id { runningActionID = nil }
    }

    /// Dismisses the transient launch-failure message (called by the UI).
    func dismissRunFailure() {
        runFailureMessage = nil
    }

    private static let runTimeoutSeconds = 6

    private func recordLaunch(of tile: Tile) {
        recents.insert(LaunchRecord(tile: tile, at: Date()), at: 0)
        if recents.count > 50 { recents.removeLast(recents.count - 50) }
        LaunchRecord.save(recents)
    }

    private func recordLaunch(of action: Action) {
        recents.insert(LaunchRecord(action: action, at: Date()), at: 0)
        if recents.count > 50 { recents.removeLast(recents.count - 50) }
        LaunchRecord.save(recents)
    }

    func clearRecents() {
        recents = []
        LaunchRecord.save(recents)
    }

    // MARK: - Disconnect

    func disconnect() async {
        reconnectTask?.cancel()
        reconnectTask = nil
        storedToken = nil
        storedMacID = nil
        await peer?.close()
        peer = nil
        tiles = []
        fipleBar = []
        macName = nil
        macKind = .laptop
        runningTileID = nil
        runningActionID = nil
        runStartedAt.removeAll()
        phase = endpoint == nil ? .searching : .readyToPair
    }

    private func handleDrop(_ peer: PeerConnection) async {
        guard self.peer === peer else { return }
        self.peer = nil
        // Nothing in flight will ever be answered on this socket; a spinner
        // left up here would spin forever.
        runningTileID = nil
        runningActionID = nil
        runStartedAt.removeAll()
        // Transient drop: auto-reconnect silently if we still trust this Mac.
        if storedToken != nil {
            FipleLog.connection.notice("connection dropped — auto-reconnecting")
            scheduleReconnect()
        } else {
            phase = endpoint == nil ? .searching : .readyToPair
        }
    }

    /// Retries the token reconnect with exponential backoff instead of giving
    /// up after one attempt (the Mac may still be waking, or Wi-Fi still
    /// re-associating). After a couple of misses the pinned endpoint is treated
    /// as stale and discovery is restarted, since the Mac may be back under a
    /// different address. Cancelled by a successful pair or explicit disconnect.
    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            var delay: Duration = .milliseconds(400)
            var misses = 0
            while !Task.isCancelled {
                guard let self else { return }
                guard self.storedToken != nil else { return }
                if self.phase == .connected { return }
                if let token = self.storedToken, self.endpoint != nil, self.peer == nil {
                    await self.authenticate(.reconnect(token: token), silent: true)
                    if self.phase == .connected { return }
                    misses += 1
                    if misses == 2 { self.restartDiscovery() }
                }
                try? await Task.sleep(for: delay)
                delay = min(delay * 2, .seconds(30))
            }
        }
    }

    /// User-facing copy for a typed rejection reason.
    private static func message(for reason: PairRejectReason) -> String {
        switch reason {
        case .incorrectCode: "Incorrect code. Check the code shown on your Mac."
        case .tooManyAttempts: "Too many attempts. Wait about 10 seconds, then enter the code again."
        case .pairingExpired: "Pairing expired. Enter the code shown on your Mac."
        }
    }

    // MARK: - Persistence

    private static let tokenKey = "fiple.token"

    /// The reconnect token is a bearer credential (full remote control of the
    /// Mac), so it lives in the Keychain, not UserDefaults.
    private var storedToken: String? {
        get { Keychain.get(Self.tokenKey) }
        set {
            if let newValue { Keychain.set(newValue, for: Self.tokenKey) }
            else { Keychain.remove(Self.tokenKey) }
        }
    }

    /// One-time migration of a token left in UserDefaults by an earlier build.
    private func migrateLegacyToken() {
        guard Keychain.get(Self.tokenKey) == nil,
              let legacy = UserDefaults.standard.string(forKey: Self.tokenKey) else { return }
        // Only scrub the plaintext copy once it is safely in the Keychain.
        if Keychain.set(legacy, for: Self.tokenKey) {
            UserDefaults.standard.removeObject(forKey: Self.tokenKey)
        }
    }

    private var storedMacID: String? {
        get { UserDefaults.standard.string(forKey: "fiple.macID") }
        set { UserDefaults.standard.set(newValue, forKey: "fiple.macID") }
    }

    // MARK: - Demo / preview fixture (debug builds only)

    #if DEBUG
    /// Puts the controller into a connected state on representative fixture tiles
    /// (workspaces + single-action apps/sites/files). Used only by `-demo` /
    /// previews so the UI can be exercised without a live Mac.
    func loadDemoFixture() {
        let demo = RemoteController.demoTiles
        macName = "MacBook Pro M3"
        tiles = demo
        fipleBar = Array(demo.flatMap(\.actions).prefix(6))
        recents = [
            LaunchRecord(tile: demo[3], at: Date().addingTimeInterval(-300)),
            LaunchRecord(tile: demo[0], at: Date().addingTimeInterval(-3600)),
            LaunchRecord(tile: demo[5], at: Date().addingTimeInterval(-7200)),
            LaunchRecord(tile: demo[2], at: Date().addingTimeInterval(-90000)),
            LaunchRecord(tile: demo[4], at: Date().addingTimeInterval(-180000)),
        ]
        phase = .connected
    }

    static let demoTiles: [Tile] = [
        Tile(name: "Start Coding", subtitle: "Everything you need to code",
             iconSystemName: "chevron.left.forwardslash.chevron.right", colorHex: "#34C759", order: 0,
             actions: [
                Action(kind: .launchApp(bundleID: "com.apple.dt.Xcode")),
                Action(kind: .openURL(URL(string: "https://github.com")!)),
                Action(kind: .launchApp(bundleID: "com.apple.Terminal")),
             ]),
        Tile(name: "Design Session", subtitle: "Design and prototype",
             iconSystemName: "pencil.and.outline", colorHex: "#8B5CF6", order: 1,
             actions: [
                Action(kind: .openURL(URL(string: "https://figma.com")!)),
                Action(kind: .openURL(URL(string: "https://dribbble.com")!)),
                Action(kind: .launchApp(bundleID: "com.apple.Preview")),
             ]),
        Tile(name: "Deep Work", subtitle: "Focus and get things done",
             iconSystemName: "target", colorHex: "#3B82F6", order: 2,
             actions: [
                Action(kind: .launchApp(bundleID: "com.apple.Notes")),
                Action(kind: .openURL(URL(string: "https://music.apple.com")!)),
             ]),
        Tile(name: "ChatGPT", iconSystemName: "sparkle", colorHex: "#10A37F", order: 3,
             actions: [Action(kind: .openURL(URL(string: "https://chatgpt.com")!))]),
        Tile(name: "Notion", iconSystemName: "note.text", colorHex: "#111111", order: 4,
             actions: [Action(kind: .openURL(URL(string: "https://notion.so")!))]),
        Tile(name: "Spotify", iconSystemName: "music.note", colorHex: "#1DB954", order: 5,
             actions: [Action(kind: .launchApp(bundleID: "com.spotify.client"))]),
    ]
    #endif
}
