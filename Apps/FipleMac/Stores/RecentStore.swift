import AppKit
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

    /// A launch of a single Fiple Bar action (app / website / file).
    @MainActor init(action: Action, at timestamp: Date) {
        id = UUID()
        tileID = action.id
        tileName = Self.name(for: action.kind)
        iconSystemName = Self.symbol(for: action.kind)
        iconImageData = action.iconImageData ?? SystemIcon.pngData(for: action.kind)
        colorHex = Self.color(for: action.kind)
        self.timestamp = timestamp
    }

    @MainActor private static func name(for kind: ActionKind) -> String {
        switch kind {
        case let .launchApp(bundleID):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            }
            return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        case let .openURL(url):
            return (url.host()?.replacingOccurrences(of: "www.", with: "")) ?? url.absoluteString
        case let .openFile(path, _):
            return (path as NSString).lastPathComponent
        }
    }

    private static func symbol(for kind: ActionKind) -> String {
        switch kind {
        case .launchApp: "app.fill"
        case .openURL: "globe"
        case .openFile: "doc.fill"
        }
    }

    private static func color(for kind: ActionKind) -> String {
        switch kind {
        case .launchApp: "#84CC16"
        case .openURL: "#0EA5E9"
        case .openFile: "#F59E0B"
        }
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

    /// Record a single Fiple Bar action launch.
    func record(_ action: Action, at date: Date = Date()) {
        records.insert(RunRecord(action: action, at: date), at: 0)
        if records.count > limit { records.removeLast(records.count - limit) }
        commit()
    }

    func delete(_ id: UUID) {
        records.removeAll { $0.id == id }
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
