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

    let macName = Host.current().localizedName ?? "Mac"
    let macID: String = ServerController.stableMacID()

    @ObservationIgnored let store: TileStore
    @ObservationIgnored private let server = FipleServer()
    @ObservationIgnored private let executor = MacActionExecutor()
    @ObservationIgnored private var peer: PeerConnection?
    @ObservationIgnored private var isPaired = false
    @ObservationIgnored private var acceptTask: Task<Void, Never>?

    /// Persistent token for the currently remembered phone. Survives Mac app
    /// restarts so a known phone reconnects silently; cleared on explicit
    /// disconnect, which forces a fresh code.
    @ObservationIgnored private var sessionToken: String?

    init(store: TileStore) {
        self.store = store
        sessionToken = UserDefaults.standard.string(forKey: Self.tokenKey)
        store.didChange = { [weak self] in
            Task { await self?.pushSnapshot() }
        }
    }

    /// Idempotent: starts advertising and accepting connections.
    func start() async {
        guard status == .idle else { return }
        regenerateCode()
        do {
            _ = try await server.start(deviceName: macName)
            status = .advertising
        } catch {
            status = .idle
            return
        }
        acceptTask = Task { [weak self] in
            guard let self else { return }
            for await peer in await self.server.newConnections {
                await self.handle(peer)
            }
        }
    }

    /// Explicit disconnect: invalidates the remembered pairing so the next
    /// connection requires a fresh code (PRD `fiple-pairing`).
    func disconnect() async {
        if let peer { await peer.close() }
        peer = nil
        isPaired = false
        sessionToken = nil
        UserDefaults.standard.removeObject(forKey: Self.tokenKey)
        status = .advertising
        regenerateCode()
    }

    // MARK: - Connection handling

    private func handle(_ peer: PeerConnection) async {
        self.peer = peer
        isPaired = false
        do {
            for try await payload in await peer.messages {
                let message = try MessageCodec.decode(ClientMessage.self, from: payload)
                await process(message, on: peer)
            }
        } catch {
            // stream ended with error — fall through to reset
        }
        if self.peer === peer { resetToAdvertising() }
    }

    private func process(_ message: ClientMessage, on peer: PeerConnection) async {
        switch message {
        case let .pair(code):
            if let current = pairingCode, code == current.value {
                await acceptPairing(on: peer)
            } else {
                try? await peer.send(ServerMessage.pairRejected(reason: "Incorrect code"))
            }

        case let .reconnect(token):
            if let saved = sessionToken, token == saved {
                await acceptPairing(on: peer)
            } else {
                try? await peer.send(ServerMessage.pairRejected(reason: "Pairing expired"))
            }

        case let .run(tileID):
            guard isPaired, let tile = store.tiles.first(where: { $0.id == tileID }) else { return }
            let result = await TileRunner(executor: executor).run(tile)
            lastRun = result
            didRun?(tile)
            try? await peer.send(ServerMessage.runResult(result))
        }
    }

    private func acceptPairing(on peer: PeerConnection) async {
        isPaired = true
        status = .connected
        let token = sessionToken ?? UUID().uuidString
        sessionToken = token
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
        try? await peer.send(ServerMessage.paired(macID: macID, macName: macName, token: token))
        try? await peer.send(ServerMessage.tilesSnapshot(tiles: store.tiles))
    }

    private func pushSnapshot() async {
        guard isPaired, let peer else { return }
        try? await peer.send(ServerMessage.tilesSnapshot(tiles: store.tiles))
    }

    // MARK: - State

    /// Transient drop (Wi-Fi blip): keep the code and token so a remembered
    /// phone reconnects silently.
    private func resetToAdvertising() {
        peer = nil
        isPaired = false
        status = .advertising
    }

    private func regenerateCode() {
        pairingCode = PairingCode.random()
    }

    private static let tokenKey = "com.fiple.sessionToken"

    /// A stable identifier for this Mac, persisted in UserDefaults.
    private static func stableMacID() -> String {
        let key = "com.fiple.macID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}
