import FipleKit
import Foundation

/// A phone-side launch event for the Recent list. Stores a denormalised snapshot
/// of the tile so history survives even if the tile is later edited on the Mac.
/// Mirrors the Mac's `RunRecord`, but lives on the remote because launch history
/// is not sent over the wire.
struct LaunchRecord: Identifiable, Codable, Equatable, Hashable {
    enum Category: String, Codable {
        case app, website, file, workspace
    }

    let id: UUID
    let tileID: UUID
    let name: String
    let iconSystemName: String
    let iconImageData: Data?
    let colorHex: String
    let category: Category
    let timestamp: Date

    init(tile: Tile, at timestamp: Date) {
        id = UUID()
        tileID = tile.id
        name = tile.name
        iconSystemName = tile.iconSystemName
        iconImageData = tile.iconImageData
        colorHex = tile.colorHex
        category = LaunchRecord.category(for: tile)
        self.timestamp = timestamp
    }

    /// A launch of a single Fiple Bar action (app / website / file).
    init(action: Action, at timestamp: Date) {
        let quick = QuickAction(action: action, tileID: action.id)
        id = UUID()
        tileID = action.id
        name = quick.title
        iconSystemName = quick.fallbackSymbol
        iconImageData = action.iconImageData
        colorHex = "#3B82F6"
        category = LaunchRecord.category(for: action.kind)
        self.timestamp = timestamp
    }

    private static func category(for kind: ActionKind) -> Category {
        switch kind {
        case .launchApp: .app
        case .openURL: .website
        case .openFile: .file
        }
    }

    /// A multi-action tile is a workspace; a single-action tile is categorised by
    /// its one action.
    private static func category(for tile: Tile) -> Category {
        if tile.isWorkspace { return .workspace }
        switch tile.actions.first?.kind {
        case .launchApp: return .app
        case .openURL: return .website
        case .openFile: return .file
        case .none: return .app
        }
    }

    /// "Today, 10:32" / "Yesterday" / "12 Jun".
    var displayTime: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(timestamp) {
            return timestamp.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(timestamp) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: timestamp, to: Date()).day ?? 0
        if days < 7 { return "\(days) days ago" }
        return timestamp.formatted(.dateTime.day().month(.abbreviated))
    }

    var categoryLabel: String {
        switch category {
        case .app: "Application"
        case .website: "Website"
        case .file: "File"
        case .workspace: "Workspace"
        }
    }

    // MARK: Persistence (UserDefaults JSON, mirroring the Mac's RecentStore cap)

    private static let key = "fiple.recents"

    static func load() -> [LaunchRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([LaunchRecord].self, from: data) else { return [] }
        return saved
    }

    static func save(_ records: [LaunchRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// One individual action surfaced in Quick Access, derived from a tile's actions.
struct QuickAction: Identifiable, Hashable {
    let id: UUID          // the action's id
    let tileID: UUID
    let kind: ActionKind
    /// The action's real icon (app icon / Finder icon) as a PNG, resolved on the
    /// Mac and carried in the tile snapshot. Nil for websites, which resolve a
    /// favicon instead.
    let iconImageData: Data?

    init(action: Action, tileID: UUID) {
        id = action.id
        self.tileID = tileID
        kind = action.kind
        iconImageData = action.iconImageData
    }

    /// De-duplication key so the same app/site/file appears once across tiles.
    var dedupeKey: String {
        switch kind {
        case let .launchApp(bundleID): "app:\(bundleID)"
        case let .openURL(url): "url:\(url.host() ?? url.absoluteString)"
        case let .openFile(path, _): "file:\(path)"
        }
    }

    /// Short human label ("Xcode", "github.com", "Roadmap.pdf").
    var title: String {
        switch kind {
        case let .launchApp(bundleID):
            (bundleID.split(separator: ".").last.map(String.init) ?? bundleID).capitalized
        case let .openURL(url):
            (url.host()?.replacingOccurrences(of: "www.", with: "")) ?? url.absoluteString
        case let .openFile(path, _):
            (path as NSString).lastPathComponent
        }
    }

    /// Favicon host for websites; nil otherwise.
    var faviconHost: String? {
        if case let .openURL(url) = kind { return url.host() }
        return nil
    }

    /// SF Symbol fallback when no real icon is available.
    var fallbackSymbol: String {
        switch kind {
        case .launchApp: "app.fill"
        case .openURL: "globe"
        case .openFile: "doc.fill"
        }
    }
}
