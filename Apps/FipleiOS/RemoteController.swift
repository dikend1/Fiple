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
    private(set) var macName: String?
    private(set) var tiles: [Tile] = []
    private(set) var pairError: String?
    private(set) var runningTileID: UUID?
    private(set) var runningActionID: UUID?
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
        discoverTask = Task { [weak self] in
            guard let self else { return }
            for await endpoint in await self.client.discover() {
                await self.found(endpoint)
            }
        }
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
            await authenticate(.reconnect(token: token))
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

    private func authenticate(_ auth: ClientMessage) async {
        guard let endpoint else { return }
        phase = .connecting
        pairError = nil
        do {
            let peer = try await client.connect(to: endpoint)
            self.peer = peer
            startReceiving(on: peer)
            try await peer.send(auth)
        } catch {
            FipleLog.pairing.error("authenticate failed: \(error.localizedDescription)")
            pairError = "Couldn't reach your Mac"
            phase = .readyToPair
        }
    }

    private func startReceiving(on peer: PeerConnection) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await payload in await peer.messages {
                    let message = try MessageCodec.decode(ServerMessage.self, from: payload)
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
            FipleLog.pairing.info("paired with '\(macName)'")
            self.macName = macName
            storedToken = token
            storedMacID = macID
            pairError = nil
            phase = .connected

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
                let ok = result.actions.allSatisfy(\.ok)
                FipleLog.execution.info("round-trip \(ms)ms — \(ok ? "ok" : "had failures")")
            }
            if runningTileID == result.tileID { runningTileID = nil }
            if runningActionID == result.tileID { runningActionID = nil }
        }
    }

    // MARK: - Triggering

    func run(_ tile: Tile) async {
        guard phase == .connected, let peer else { return }
        FipleLog.execution.info("triggering tile '\(tile.name)'")
        runningTileID = tile.id
        runStartedAt[tile.id] = Date()
        recordLaunch(of: tile)
        try? await peer.send(ClientMessage.run(tileID: tile.id))
    }

    /// Trigger a single Fiple Bar action on the Mac.
    func runAction(_ action: Action) async {
        guard phase == .connected, let peer else { return }
        FipleLog.execution.info("triggering action: \(action.displayLabel)")
        runningActionID = action.id
        runStartedAt[action.id] = Date()
        recordLaunch(of: action)
        // Send only the id; the Mac resolves and runs it from its own Fiple Bar.
        try? await peer.send(ClientMessage.runAction(actionID: action.id))
    }

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
        storedToken = nil
        storedMacID = nil
        await peer?.close()
        peer = nil
        tiles = []
        macName = nil
        phase = endpoint == nil ? .searching : .readyToPair
    }

    private func handleDrop(_ peer: PeerConnection) async {
        guard self.peer === peer else { return }
        self.peer = nil
        // Transient drop: auto-reconnect silently if we still trust this Mac.
        if let token = storedToken, endpoint != nil {
            FipleLog.connection.notice("connection dropped — auto-reconnecting")
            await authenticate(.reconnect(token: token))
        } else {
            phase = endpoint == nil ? .searching : .readyToPair
        }
    }

    /// User-facing copy for a typed rejection reason.
    private static func message(for reason: PairRejectReason) -> String {
        switch reason {
        case .incorrectCode: "Incorrect code. Check the code shown on your Mac."
        case .tooManyAttempts: "Too many attempts. A new code is shown on your Mac — wait a moment and use it."
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
        Tile(name: "Morning Routine", iconSystemName: "bolt.fill", colorHex: "#E5483D", order: 5,
             actions: [Action(kind: .runShortcut(name: "Morning Routine"))]),
    ]
    #endif
}
