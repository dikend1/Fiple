import FipleKit
import Foundation
import Observation

/// A single launch event, shown in the "Recent" list. It stores a denormalised
/// snapshot of the tile (name, icon, colour) so history survives even if the
/// originating tile is later edited or deleted.
struct RunRecord: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    let tileID: UUID
    let tileName: String
    let iconSystemName: String
    let iconImageData: Data?
    let colorHex: String
    let timestamp: Date

    init(tile: Tile, at timestamp: Date) {
        id = UUID()
        tileID = tile.id
        tileName = tile.name
        iconSystemName = tile.iconSystemName
        iconImageData = tile.iconImageData
        colorHex = tile.colorHex
        self.timestamp = timestamp
    }
}

/// Mac-local launch history, persisted as JSON in Application Support. Newest
/// first, capped so the file can't grow without bound.
@MainActor
@Observable
final class RecentStore {
    private(set) var records: [RunRecord]

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let limit = 50

    init() {
        fileURL = AppSupport.fileURL(named: "recents.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([RunRecord].self, from: data) {
            records = saved
        } else {
            records = []
        }
    }

    /// Record a launch. Date is injected so this stays testable and pure.
    func record(_ tile: Tile, at date: Date = Date()) {
        records.insert(RunRecord(tile: tile, at: date), at: 0)
        if records.count > limit { records.removeLast(records.count - limit) }
        commit()
    }

    func clear() {
        records.removeAll()
        commit()
    }

    private func commit() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

/// Shared helper for the app's Application Support directory.
enum AppSupport {
    static func fileURL(named name: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Fiple", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }
}
