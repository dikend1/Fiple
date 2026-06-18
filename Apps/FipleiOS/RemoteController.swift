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
    private(set) var runResults: [UUID: RunResult] = [:]

    @ObservationIgnored private let client = FipleClient()
    @ObservationIgnored private var peer: PeerConnection?
    @ObservationIgnored private var endpoint: NWEndpoint?
    @ObservationIgnored private var discoverTask: Task<Void, Never>?
    @ObservationIgnored private var receiveTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func begin() {
        guard discoverTask == nil else { return }
        phase = .searching
        discoverTask = Task { [weak self] in
            guard let self else { return }
            for await endpoint in await self.client.discover() {
                await self.found(endpoint)
            }
        }
    }

    private func found(_ endpoint: NWEndpoint) async {
        guard self.endpoint == nil else { return } // MVP: first Mac wins
        self.endpoint = endpoint
        if let token = storedToken {
            await authenticate(.reconnect(token: token))
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
            self.macName = macName
            storedToken = token
            storedMacID = macID
            pairError = nil
            phase = .connected

        case let .pairRejected(reason):
            // a rejected reconnect means the remembered pairing is stale
            storedToken = nil
            await peer?.close()
            peer = nil
            pairError = reason
            phase = .readyToPair

        case let .tilesSnapshot(tiles):
            self.tiles = tiles.sorted { $0.order < $1.order }

        case let .runResult(result):
            runResults[result.tileID] = result
            if runningTileID == result.tileID { runningTileID = nil }
        }
    }

    // MARK: - Triggering

    func run(_ tile: Tile) async {
        guard phase == .connected, let peer else { return }
        runningTileID = tile.id
        try? await peer.send(ClientMessage.run(tileID: tile.id))
    }

    // MARK: - Disconnect

    func disconnect() async {
        storedToken = nil
        storedMacID = nil
        await peer?.close()
        peer = nil
        tiles = []
        macName = nil
        runResults = [:]
        phase = endpoint == nil ? .searching : .readyToPair
    }

    private func handleDrop(_ peer: PeerConnection) async {
        guard self.peer === peer else { return }
        self.peer = nil
        // Transient drop: auto-reconnect silently if we still trust this Mac.
        if let token = storedToken, endpoint != nil {
            await authenticate(.reconnect(token: token))
        } else {
            phase = endpoint == nil ? .searching : .readyToPair
        }
    }

    // MARK: - Persistence

    private var storedToken: String? {
        get { UserDefaults.standard.string(forKey: "fiple.token") }
        set { UserDefaults.standard.set(newValue, forKey: "fiple.token") }
    }

    private var storedMacID: String? {
        get { UserDefaults.standard.string(forKey: "fiple.macID") }
        set { UserDefaults.standard.set(newValue, forKey: "fiple.macID") }
    }
}
