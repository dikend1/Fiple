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
        dropLegacyDemoTiles()
    }

    /// 1.0 seeded four demo workspaces on first launch; 1.1 starts empty. This
    /// one-time migration removes those templates from old installs so an
    /// update also lands "like new" — but only tiles the user never touched
    /// (recognition lives in `LegacyDemoSeed`, unit-tested in FipleKit). A
    /// renamed or edited demo tile is the user's own work now and stays.
    private func dropLegacyDemoTiles() {
        let flag = "fiple.migration.dropDemoSeed"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        let remaining = LegacyDemoSeed.nonDemoTiles(tiles)
        guard remaining.count != tiles.count else { return }
        tiles = remaining
        commit()
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
