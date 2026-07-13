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

    /// Terminal service state advertised by the Mac over the tile channel.
    private(set) var terminalEnabled = false
    private(set) var terminalPort: UInt16 = 0
    /// The Mac's resolved address, reused from the live tile connection.
    private(set) var terminalHost: String?

    /// Everything the terminal screen needs to open a session, or nil when the
    /// Mac hasn't enabled the feature (or we're not connected).
    var terminalTarget: (host: String, port: UInt16, token: String)? {
        guard terminalEnabled, terminalPort != 0,
              let terminalHost, let token = storedToken else { return nil }
        return (terminalHost, terminalPort, token)
    }
    /// Smart Trash candidates synced from the Mac (metadata only; files stay on
    /// the Mac). Sorted by nearest deadline so the most urgent items lead.
    private(set) var trashCandidates: [TrashCandidate] = []
    /// Lazily fetched QuickLook thumbnails, keyed by candidate id.
    private(set) var trashThumbnails: [UUID: Data] = [:]
    /// Set while a batch review decision is in flight (disables the action bar).
    private(set) var trashActionInFlight = false
    /// The swipe-deck review state. Lives here — not in the screen — so leaving
    /// Smart Trash and coming back keeps the basket and progress; the staged
    /// ids also persist across relaunches (restored on the next snapshot).
    private(set) var trashSession = TrashReviewSession(candidates: [])

    /// Phone-side launch history. The Mac keeps its own `RecentStore`, but it is
    /// not sent over the wire, so the remote records what *it* triggers — newest
    /// first, capped and persisted so it survives relaunch.
    private(set) var recents: [LaunchRecord] = []

    /// Fiple Pro entitlement + purchase state. Injected so it can be shared with
    /// the paywall and stubbed in tests/previews.
    let entitlements: EntitlementStore

    /// Set when the user taps a locked workspace; the UI presents the paywall and
    /// resets it on dismiss.
    var paywallRequested = false

    #if DEBUG
    /// Debug-only: Settings → Replay onboarding sets this; RootView shows the
    /// welcome flow again and clears it.
    var replayWelcomeRequested = false
    #endif

    init(entitlements: EntitlementStore = EntitlementStore()) {
        self.entitlements = entitlements
    }

    /// Workspaces are multi-action tiles; single-action tiles are "quick access".
    var workspaces: [Tile] { tiles.filter(\.isWorkspace) }

    #if DEBUG
    /// Debug-only override of the free limit, so the locked state can be exercised
    /// without needing 9+ real items. `nil` uses the default (8).
    var debugFreeLimitOverride: Int?
    #endif

    /// Free-tier limits per gated phone surface. The Fiple Bar (quick-launch apps)
    /// is the lightweight free hook so it allows more; workspace presets are the
    /// premium value, so far fewer are free.
    static let freeFipleBarLimit = 8
    static let freeWorkspaceLimit = 2

    /// Applies the per-surface base limit, or the DEBUG override when set.
    private func freeLimit(_ base: Int) -> Int {
        #if DEBUG
        if let override = debugFreeLimitOverride { return override }
        #endif
        return base
    }

    /// Fiple Bar actions locked behind Fiple Pro — the ones past the free limit
    /// while not Pro. The first 8 quick-launch apps stay free.
    var lockedFipleBarActionIDs: Set<UUID> {
        FreeTierGate.lockedIDs(fipleBar, freeLimit: freeLimit(Self.freeFipleBarLimit), isPro: entitlements.isPro)
    }

    /// Workspace presets locked behind Fiple Pro — past the free limit while not
    /// Pro. The first 2 workspaces stay free.
    var lockedWorkspaceIDs: Set<UUID> {
        FreeTierGate.lockedIDs(workspaces, freeLimit: freeLimit(Self.freeWorkspaceLimit), isPro: entitlements.isPro)
    }

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
        normalizeTokenAccessGroup()
        recents = LaunchRecord.load()
        #if DEBUG
        // Offline demo mode (`-demo` launch arg / SwiftUI previews): skip discovery
        // and present the connected UI on fixture tiles, so the screens can be
        // exercised without a paired Mac. Debug builds only.
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            loadDemoFixture()
            // Auto-present the paywall for App Store review screenshots.
            if ProcessInfo.processInfo.arguments.contains("-paywall") {
                paywallRequested = true
            }
            return
        }
        #endif
        phase = .searching
        startDiscovery()
    }

    private func startDiscovery() {
        discoverTask?.cancel()
        discovered.removeAll()
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

    /// Every Mac discovered on the LAN this browse. Several Macs can advertise
    /// Fiple on the same network (a shared office / home Wi-Fi), so the first one
    /// to answer is not necessarily *yours* — the old "first Mac wins" rule meant
    /// a friend's Mac could grab the connection and reject your code. The pairing
    /// code (or reconnect token), tried against each Mac in turn, is what decides
    /// which Mac to connect to.
    @ObservationIgnored private var discovered: [NWEndpoint] = []

    /// An in-flight pairing / reconnect attempt that walks the discovered Macs
    /// one at a time until one accepts. `tried` remembers the Macs already ruled
    /// out so each is attempted once. A rejection advances to the next Mac; only
    /// when every Mac has been ruled out does the attempt surface a failure.
    private struct Sweep {
        let auth: ClientMessage
        let silent: Bool
        var tried: Set<NWEndpoint> = []
    }
    @ObservationIgnored private var sweep: Sweep?

    private func found(_ endpoint: NWEndpoint) async {
        if !discovered.contains(endpoint) { discovered.append(endpoint) }
        FipleLog.discovery.info("Mac found on LAN")

        // A sweep is already walking the Macs. This new one is now in
        // `discovered`, so the sweep will reach it if its current candidate
        // fails — don't start a second attempt in parallel.
        if sweep != nil { return }

        // Only searching / ready-to-pair start a fresh attempt; when already
        // connecting or connected there's nothing to kick off.
        guard phase == .searching || phase == .readyToPair else { return }

        if let token = storedToken {
            FipleLog.pairing.info("auto-reconnecting with stored token")
            await startSweep(.reconnect(token: token), silent: true)
        } else if let pending = pendingCode {
            pendingCode = nil
            await startSweep(.pair(code: pending.value), silent: false)
        } else {
            phase = .readyToPair
        }
    }

    // MARK: - Pairing sweep

    /// Begin trying `auth` against the Macs on the LAN, starting with the first
    /// one we haven't ruled out yet.
    private func startSweep(_ auth: ClientMessage, silent: Bool) async {
        sweep = Sweep(auth: auth, silent: silent)
        await advanceSweep()
    }

    /// Attempt the next not-yet-tried Mac in the current sweep. With none left,
    /// the attempt is finished — see `finishSweep`.
    private func advanceSweep() async {
        guard var current = sweep else { return }
        guard let next = discovered.first(where: { !current.tried.contains($0) }) else {
            await finishSweep()
            return
        }
        current.tried.insert(next)
        sweep = current
        endpoint = next
        await authenticate(current.auth, silent: current.silent)
    }

    /// Every discovered Mac rejected the credential (or was unreachable). A
    /// reconnect sweep just means our Mac isn't on the network right now — keep
    /// the token and stay quiet. A code sweep means the code matched no Mac
    /// present, so surface that.
    private func finishSweep() async {
        guard let current = sweep else { return }
        sweep = nil
        if case .reconnect = current.auth {
            phase = .searching
        } else {
            pendingCode = nil
            pairError = "Incorrect code. Check the code shown on your Mac."
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
        guard !discovered.isEmpty else {
            pendingCode = parsed
            pairError = nil
            return
        }
        await startSweep(.pair(code: parsed.value), silent: false)
    }

    /// `silent` marks background auto-reconnect attempts: their failures must
    /// not bounce the UI into the pairing flow or surface an error — the phone
    /// may simply be off the Mac's network, which the tabbed UI already handles.
    private func authenticate(_ auth: ClientMessage, silent: Bool = false, timeout: Duration = .seconds(10)) async {
        guard let endpoint else { return }
        if case .reconnect = auth { pendingAuthIsReconnect = true } else { pendingAuthIsReconnect = false }
        // A silent auto-reconnect keeps the current UI (usually `.connected`) so a
        // brief Wi-Fi drop doesn't flash the connecting/pairing screen; the phase
        // only moves if the reconnect actually fails or is rejected. Interactive
        // pairing shows connecting progress as usual.
        if !silent { phase = .connecting }
        pairError = nil
        do {
            let peer = try await client.connect(to: endpoint, timeout: timeout)
            self.peer = peer
            startReceiving(on: peer)
            try await peer.send(auth)
        } catch {
            FipleLog.pairing.error("authenticate failed: \(error.localizedDescription)")
            // Mid-sweep an unreachable Mac is simply the wrong (or absent) one —
            // move on to the next candidate instead of failing the whole attempt.
            if sweep != nil {
                await advanceSweep()
            } else if silent {
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
            // The message stream *finishing* (no throw) means the Mac closed the
            // socket cleanly — a deliberate quit / sleep / disconnect. A thrown
            // error is an unclean drop (reset, timeout) that may just be a
            // transient network blip. We treat the two very differently below.
            var deliberate = true
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
                deliberate = false
            }
            await self.handleDrop(peer, deliberate: deliberate)
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
                // The wrong Mac answered our token. Mid-sweep that just means
                // this isn't our Mac — move on without disturbing the token.
                if sweep != nil {
                    await peer?.close()
                    peer = nil
                    await advanceSweep()
                    return
                }
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
            sweep = nil
            pendingCode = nil
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
            FipleLog.pairing.notice("pair rejected: \(reason.rawValue)")
            await peer?.close()
            peer = nil
            // Mid-sweep this Mac rejected us, but another on the LAN might
            // accept. Try the next one; the token stays put until every Mac has
            // been ruled out.
            if sweep != nil {
                await advanceSweep()
                return
            }
            // A rejected reconnect (outside a sweep) means the remembered pairing
            // is stale.
            storedToken = nil
            pairError = Self.message(for: reason)
            phase = .readyToPair

        case let .tilesSnapshot(tiles):
            FipleLog.pairing.debug("received \(tiles.count) tile(s)")
            self.tiles = tiles.sorted { $0.order < $1.order }

        case let .fipleBar(actions):
            self.fipleBar = actions

        case let .terminalService(enabled, port):
            terminalEnabled = enabled
            terminalPort = port
            // Reuse the Mac address the tile channel already resolved, so the
            // terminal connects without a second Bonjour lookup.
            terminalHost = await peer?.remoteHost()
            FipleLog.connection.info("terminal service \(enabled ? "on port \(port)" : "off")")

        case let .trashCandidates(candidates):
            trashCandidates = candidates.sorted { $0.deadline < $1.deadline }
            // Drop thumbnails for candidates that left the list.
            trashThumbnails = trashThumbnails.filter { id, _ in
                candidates.contains { $0.id == id }
            }
            TrashReminder.reschedule(for: trashCandidates)
            syncTrashSession()

        case let .trashThumbnail(candidateID, jpeg):
            trashThumbnails[candidateID] = jpeg

        case let .beamResult(_, ok, message):
            beamState = ok
                ? .done(fileName: message ?? "File")
                : .failed(message ?? "The Mac couldn't save the file")
            beamContinuation?.resume()
            beamContinuation = nil
            beamWaitID = nil

        case .trashActionResult:
            // The fresh candidate snapshot follows separately; this just
            // releases the action bar.
            trashActionInFlight = false

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
        // Locked workspace (past the free limit, not Pro): show the paywall
        // instead of running it.
        if lockedWorkspaceIDs.contains(tile.id) {
            FipleLog.execution.info("tile '\(tile.name)' is locked — presenting paywall")
            paywallRequested = true
            return
        }
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
        // Locked quick-launch app (past the free limit, not Pro): show the paywall.
        if lockedFipleBarActionIDs.contains(action.id) {
            FipleLog.execution.info("action '\(action.displayLabel)' is locked — presenting paywall")
            paywallRequested = true
            return
        }
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

    /// Whether a Mac is currently connected — used by the global gesture layer to
    /// decide between a "sent" and a "declined" haptic before it even sends.
    var isConnected: Bool { phase == .connected }

    /// Send a recognized multi-touch gesture to the Mac. Fire-and-forget, like a
    /// tile run: there is no result frame. Returns whether it was actually sent
    /// (a Mac is connected and the send succeeded) so the caller can pick the
    /// right haptic.
    @discardableResult
    func sendGesture(_ action: GestureAction) async -> Bool {
        guard phase == .connected, let peer else { return false }
        do {
            try await peer.send(ClientMessage.gesture(action))
            FipleLog.execution.info("sent gesture \(action.rawValue)")
            return true
        } catch {
            FipleLog.execution.error("gesture send failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Beam (send file / clipboard text to the Mac)

    enum BeamState: Equatable {
        case idle
        case sending(progress: Double)
        case done(fileName: String)
        case failed(String)
    }
    private(set) var beamState: BeamState = .idle
    @ObservationIgnored private var beamContinuation: CheckedContinuation<Void, Never>?
    /// Identifies the transfer the current continuation belongs to, so a stale
    /// 15s timeout from a *previous* transfer can never kill the next one's wait.
    @ObservationIgnored private var beamWaitID: UUID?

    // 4 MB raw is the sweet spot: base64 in the JSON frame inflates it to
    // ~5.4 MB, safely under FrameCodec's 8 MB cap, with 4× fewer
    // encode/await cycles than 1 MB chunks.
    private static let beamChunkSize = 4 * 1024 * 1024

    /// Streams a file to the Mac's Downloads in ~1 MB chunks, driving
    /// `beamState` for the progress UI. One transfer at a time.
    func beamFile(name: String, data: Data) async {
        guard phase == .connected, let peer else {
            beamState = .failed("Not connected to your Mac")
            return
        }
        guard case .sending = beamState else {
            let transferID = UUID()
            beamState = .sending(progress: 0)
            do {
                try await peer.send(ClientMessage.beamBegin(
                    transferID: transferID, name: name, totalBytes: Int64(data.count)
                ))
                var sent = 0
                while sent < data.count {
                    let end = min(sent + Self.beamChunkSize, data.count)
                    // Chunks go as raw binary frames — no base64/JSON on the
                    // hot path (BeamBinary); begin/end stay JSON.
                    try await peer.sendRaw(BeamBinary.encodeChunk(
                        transferID: transferID, bytes: data[sent ..< end]
                    ))
                    sent = end
                    beamState = .sending(progress: Double(sent) / Double(data.count))
                }
                try await peer.send(ClientMessage.beamEnd(transferID: transferID))
                // The result lands via `beamResult`; time out rather than spin
                // forever if the Mac never answers. The timeout is keyed to THIS
                // transfer so it can't fire into a later one's wait.
                await withCheckedContinuation { continuation in
                    beamContinuation = continuation
                    beamWaitID = transferID
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(15))
                        guard let self, self.beamWaitID == transferID,
                              self.beamContinuation != nil else { return }
                        self.beamState = .failed("The Mac didn't confirm the transfer")
                        self.beamContinuation?.resume()
                        self.beamContinuation = nil
                        self.beamWaitID = nil
                    }
                }
            } catch {
                FipleLog.execution.error("beam failed: \(error.localizedDescription)")
                beamState = .failed("Couldn't reach your Mac — nothing was sent")
            }
            return
        }
    }

    /// Puts text on the Mac's clipboard (QR / live-text bridge). Returns whether
    /// the send succeeded.
    @discardableResult
    func sendClipboard(text: String) async -> Bool {
        guard phase == .connected, let peer else { return false }
        do {
            try await peer.send(ClientMessage.setClipboard(text: text))
            return true
        } catch {
            return false
        }
    }

    func resetBeamState() { beamState = .idle }

    // MARK: - Smart Trash

    /// Ask the Mac for one candidate's thumbnail (per visible grid cell). The
    /// reply lands in `trashThumbnails` via the message stream.
    func requestTrashThumbnail(_ id: UUID) async {
        guard phase == .connected, let peer, trashThumbnails[id] == nil else { return }
        try? await peer.send(ClientMessage.trashThumbnail(candidateID: id))
    }

    /// Send a batch review decision. Ids only — the Mac resolves them against
    /// its own store and pushes back the updated candidate list.
    func sendTrashAction(ids: [UUID], decision: TrashDecision) async {
        guard phase == .connected, let peer, !ids.isEmpty else { return }
        trashActionInFlight = true
        do {
            try await peer.send(ClientMessage.trashAction(ids: ids, decision: decision))
        } catch {
            FipleLog.execution.error("trashAction send failed: \(error.localizedDescription)")
            trashActionInFlight = false
        }
    }

    // MARK: Swipe-deck session

    /// Re-syncs the review session with the authoritative snapshot: vanished
    /// candidates leave the deck/basket, new ones join (biggest first — the
    /// screen's promise is "free up 1,3 GB"), and a basket persisted from a
    /// previous run is restored before the saved ids are re-pruned.
    private func syncTrashSession() {
        trashSession.reconcile(with: trashCandidates.sorted { $0.sizeBytes > $1.sizeBytes })
        let saved = UserDefaults.standard.stringArray(forKey: Self.stagedIDsKey) ?? []
        trashSession.stage(ids: Set(saved.compactMap(UUID.init)))
        persistStagedIDs()
    }

    /// The basket must survive app relaunches (the deck would otherwise
    /// resurface files the user already threw out). Only the ids are stored;
    /// the candidates themselves always come from the Mac's snapshot.
    private func persistStagedIDs() {
        UserDefaults.standard.set(
            trashSession.staged.map(\.id.uuidString), forKey: Self.stagedIDsKey
        )
    }

    private static let stagedIDsKey = "com.fiple.trash.stagedIDs"

    func trashSwipe(_ decision: TrashDecision) {
        trashSession.swipe(decision)
        persistStagedIDs()
    }

    func trashUndo() {
        _ = trashSession.undo()
        persistStagedIDs()
    }

    func trashReturnToDeck(id: UUID) {
        trashSession.returnToDeck(id: id)
        persistStagedIDs()
    }

    /// "Empty (N)": one batch trash action plus any pending keeps. Connected
    /// only — otherwise the basket stays put instead of silently vanishing.
    func trashCommitBasket() async {
        guard phase == .connected else { return }
        let trashIDs = trashSession.takeTrashIDs()
        let keepIDs = trashSession.takeKeepIDs()
        persistStagedIDs()
        await sendTrashAction(ids: trashIDs, decision: .trash)
        await sendTrashAction(ids: keepIDs, decision: .keep)
    }

    /// Keeps are safe to apply without confirmation; flushed when leaving the
    /// review screen.
    func trashFlushKeeps() async {
        let keepIDs = trashSession.takeKeepIDs()
        await sendTrashAction(ids: keepIDs, decision: .keep)
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
        sweep = nil
        storedToken = nil
        storedMacID = nil
        await peer?.close()
        peer = nil
        tiles = []
        fipleBar = []
        terminalEnabled = false
        terminalPort = 0
        terminalHost = nil
        trashCandidates = []
        trashThumbnails = [:]
        trashActionInFlight = false
        // A fresh pairing may be a different Mac — its candidates have new ids,
        // so the old basket (session + persisted ids) is meaningless.
        trashSession = TrashReviewSession(candidates: [])
        UserDefaults.standard.removeObject(forKey: Self.stagedIDsKey)
        macName = nil
        macKind = .laptop
        runningTileID = nil
        runningActionID = nil
        runStartedAt.removeAll()
        phase = discovered.isEmpty ? .searching : .readyToPair
    }

    private func handleDrop(_ peer: PeerConnection, deliberate: Bool) async {
        guard self.peer === peer else { return }
        self.peer = nil
        // Nothing in flight will ever be answered on this socket; a spinner
        // left up here would spin forever.
        runningTileID = nil
        runningActionID = nil
        runStartedAt.removeAll()
        guard storedToken != nil else {
            phase = discovered.isEmpty ? .searching : .readyToPair
            return
        }
        // A clean close means the Mac went away on purpose (quit / sleep /
        // explicit disconnect) — reflect that immediately instead of pretending
        // we're still connected to a Mac that's gone. An unclean error keeps the
        // connected UI for the brief reconnect window so a transient Wi-Fi blip
        // doesn't flash the searching screen. Either way we still try a silent
        // token reconnect: if the Mac comes back we slide straight into it.
        if deliberate {
            tiles = []
            fipleBar = []
            phase = discovered.isEmpty ? .searching : .readyToPair
            FipleLog.connection.notice("connection closed cleanly — Mac went away")
        } else {
            FipleLog.connection.notice("connection dropped — auto-reconnecting")
        }
        scheduleReconnect()
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
                // We're genuinely back only when a *live socket* is paired again.
                // Don't gate on `phase` alone: after a drop the UI intentionally
                // stays `.connected` (to avoid flicker) while `peer` is nil, so
                // gating this loop on `phase == .connected` made it return on the
                // very first tick and never retry — leaving the phone stuck showing
                // "connected" to a Mac that had gone away or disconnected it.
                if self.peer != nil, self.phase == .connected { return }
                if let token = self.storedToken, self.endpoint != nil, self.peer == nil {
                    // A short deadline so a truly-gone Mac (whose withdrawn Bonjour
                    // service leaves the connect stuck in `.waiting`) surfaces as
                    // "offline" in a few seconds instead of ~10.
                    await self.authenticate(.reconnect(token: token), silent: true, timeout: .seconds(4))
                    misses += 1
                    if misses == 2 {
                        // Reconnect has clearly failed — we're offline now, so
                        // drop the cached workspaces / Fiple Bar rather than keep
                        // showing a stale snapshot (e.g. a workspace already
                        // deleted on the Mac). A fresh snapshot arrives on the
                        // next successful connect.
                        self.tiles = []
                        self.fipleBar = []
                        self.restartDiscovery()
                    }
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

    /// Re-adds the token so it lands in the app's *first* keychain access group
    /// — the one shared with the FipleShare extension. An update-in-place would
    /// leave a pre-existing item in the old app-private group forever, where
    /// the extension can't read it.
    private func normalizeTokenAccessGroup() {
        guard let token = Keychain.get(Self.tokenKey) else { return }
        Keychain.remove(Self.tokenKey)
        Keychain.set(token, for: Self.tokenKey)
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
        trashCandidates = [
            TrashCandidate(path: "/Users/demo/Downloads/Invoice-Q3-final.pdf", sizeBytes: 2_400_000,
                           lastOpened: Date().addingTimeInterval(-70 * 86_400), addedAt: Date().addingTimeInterval(-6 * 86_400),
                           deadline: Date().addingTimeInterval(1 * 86_400)),
            TrashCandidate(path: "/Users/demo/Downloads/screen-recording-standup.mov", sizeBytes: 184_000_000,
                           lastOpened: Date().addingTimeInterval(-90 * 86_400), addedAt: Date().addingTimeInterval(-3 * 86_400),
                           deadline: Date().addingTimeInterval(4 * 86_400)),
            TrashCandidate(path: "/Users/demo/Downloads/node-v20-installer.pkg", sizeBytes: 61_500_000,
                           lastOpened: Date().addingTimeInterval(-120 * 86_400), addedAt: Date().addingTimeInterval(-2 * 86_400),
                           deadline: Date().addingTimeInterval(5 * 86_400)),
            TrashCandidate(path: "/Users/demo/Downloads/IMG_4821 copy.HEIC", sizeBytes: 4_100_000,
                           lastOpened: Date().addingTimeInterval(-65 * 86_400), addedAt: Date().addingTimeInterval(-1 * 86_400),
                           deadline: Date().addingTimeInterval(6 * 86_400)),
            TrashCandidate(path: "/Users/demo/Downloads/design-assets-v2.zip", sizeBytes: 320_000_000,
                           lastOpened: Date().addingTimeInterval(-80 * 86_400), addedAt: Date(),
                           deadline: Date().addingTimeInterval(7 * 86_400)),
        ]
        // Fixture ids are minted per launch, so skip the persisted-basket
        // restore (and never let demo state clobber a real saved basket).
        trashSession = TrashReviewSession(
            candidates: trashCandidates.sorted { $0.sizeBytes > $1.sizeBytes }
        )
        phase = .connected
    }

    static let demoTiles: [Tile] = [
        Tile(name: "Start Coding", subtitle: "Everything you need to code",
             iconSystemName: "chevron.left.forwardslash.chevron.right", colorHex: "#2DA44E", order: 0,
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
