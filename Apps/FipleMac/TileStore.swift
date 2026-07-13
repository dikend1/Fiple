import FipleKit
import Foundation
import Observation

/// Source-of-truth tile storage on the Mac, persisted as JSON in Application
/// Support. The `didChange` hook lets the server push a fresh snapshot whenever
/// tiles are mutated.
@MainActor
@Observable
final class TileStore {
    private(set) var tiles: [Tile]

    /// Called after any mutation so the server can re-send a snapshot.
    @ObservationIgnored var didChange: (() -> Void)?

    @ObservationIgnored private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Fiple", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("tiles.json")

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Tile].self, from: data) {
            tiles = saved.sorted { $0.order < $1.order }
        } else {
            // A fresh install starts EMPTY — the user builds their own
            // workspaces. Demo seed tiles confused real users (a new user saw
            // someone else's "ready-made" setup on first launch).
            tiles = []
        }
    }

    func add(_ tile: Tile) {
        var tile = tile
        tile.order = (tiles.map(\.order).max() ?? -1) + 1
        tiles.append(tile)
        commit()
    }

    func update(_ tile: Tile) {
        guard let index = tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        tiles[index] = tile
        commit()
    }

    func delete(_ id: UUID) {
        tiles.removeAll { $0.id == id }
        commit()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        tiles.move(fromOffsets: fromOffsets, toOffset: toOffset)
        normalizeOrder()
        commit()
    }

    private func normalizeOrder() {
        for index in tiles.indices { tiles[index].order = index }
    }

    private func commit() {
        normalizeOrder()
        if let data = try? JSONEncoder().encode(tiles) {
            try? data.write(to: fileURL, options: .atomic)
        }
        didChange?()
    }

}
