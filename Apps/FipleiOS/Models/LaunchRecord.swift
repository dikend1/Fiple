import FipleKit
import Foundation

/// A phone-side launch event for the Recent list. Stores a denormalised snapshot
/// of the tile so history survives even if the tile is later edited on the Mac.
/// Mirrors the Mac's `RunRecord`, but lives on the remote because launch history
/// is not sent over the wire.
struct LaunchRecord: Identifiable, Codable, Equatable, Hashable {
    enum Category: String, Codable {
        case app, website, shortcut, workspace
    }

    let id: UUID
    let tileID: UUID
    let name: String
    let iconSystemName: String
    let iconImageData: Data?
    let colorHex: String
    let category: Category
    let timestamp: Date
    /// Set for single-action launches (Fiple Bar) so the row can be re-run by
    /// re-dispatching the action; nil for workspace/tile launches, which are
    /// re-run by tile id. Optional, so older saved history decodes unchanged.
    let actionKind: ActionKind?

    init(tile: Tile, at timestamp: Date) {
        id = UUID()
        tileID = tile.id
        name = tile.name
        iconSystemName = tile.iconSystemName
        iconImageData = tile.iconImageData
        colorHex = tile.colorHex
        category = LaunchRecord.category(for: tile)
        actionKind = nil
        self.timestamp = timestamp
    }

    /// A launch of a single Fiple Bar action (app / website / shortcut).
    init(action: Action, at timestamp: Date) {
        let quick = QuickAction(action: action, tileID: action.id)
        id = UUID()
        tileID = action.id
        name = quick.title
        iconSystemName = quick.fallbackSymbol
        iconImageData = action.iconImageData
        colorHex = "#3B82F6"
        category = LaunchRecord.category(for: action.kind)
        actionKind = action.kind
        self.timestamp = timestamp
    }

    /// Reconstructs the action for a single-action record so it can be re-run.
    /// Returns nil for workspace/tile records.
    var replayAction: Action? {
        guard let actionKind else { return nil }
        return Action(id: tileID, kind: actionKind, iconImageData: iconImageData, displayName: name)
    }

    /// Host for a website launch, so the row can show its favicon instead of a
    /// globe. Nil for apps, shortcuts and multi-action workspaces.
    var faviconHost: String? {
        if case let .openURL(url)? = actionKind { return url.host() }
        return nil
    }

    private static func category(for kind: ActionKind) -> Category {
        switch kind {
        case .launchApp: .app
        case .openURL: .website
        case .runShortcut: .shortcut
        }
    }

    /// A multi-action tile is a workspace; a single-action tile is categorised by
    /// its one action.
    private static func category(for tile: Tile) -> Category {
        if tile.isWorkspace { return .workspace }
        switch tile.actions.first?.kind {
        case .launchApp: return .app
        case .openURL: return .website
        case .runShortcut: return .shortcut
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
        case .shortcut: "Shortcut"
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
    /// The action's real app icon as a PNG, resolved on the Mac and carried in
    /// the tile snapshot. Nil for websites (favicon) and shortcuts (SF Symbol).
    let iconImageData: Data?
    /// The app's real display name, resolved on the Mac. Preferred over a
    /// name derived from the bundle id, which mangles apps like Books / Cursor.
    let displayName: String?

    init(action: Action, tileID: UUID) {
        id = action.id
        self.tileID = tileID
        kind = action.kind
        iconImageData = action.iconImageData
        displayName = action.displayName
    }

    /// De-duplication key so the same app/site/shortcut appears once across tiles.
    var dedupeKey: String {
        switch kind {
        case let .launchApp(bundleID): "app:\(bundleID)"
        case let .openURL(url): "url:\(url.host() ?? url.absoluteString)"
        case let .runShortcut(name): "shortcut:\(name)"
        }
    }

    /// Short human label ("Xcode", "YouTube", "Morning Routine").
    var title: String {
        switch kind {
        case let .launchApp(bundleID):
            // Prefer the Mac-resolved name; fall back to deriving from the id.
            if let displayName, !displayName.isEmpty { return displayName }
            return appTitle(for: bundleID)
        case let .openURL(url):
            return websiteTitle(for: url)
        case let .runShortcut(name):
            return name
        }
    }

    private func appTitle(for bundleID: String) -> String {
        let normalized = bundleID.lowercased()
        let knownApps: [(String, String)] = [
            ("com.microsoft.vscode", "VS Code"),
            ("claudefordesktop", "Claude"),
            ("com.openai.chat", "ChatGPT"),
            ("chatgpt", "ChatGPT"),
            ("notion", "Notion"),
            ("telegram", "Telegram")
        ]

        if let match = knownApps.first(where: { normalized.contains($0.0) }) {
            return match.1
        }

        let rawName = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        return prettifiedName(rawName)
    }

    private func websiteTitle(for url: URL) -> String {
        guard let host = url.host()?.replacingOccurrences(of: "www.", with: "") else {
            return url.absoluteString
        }

        let baseName = host.split(separator: ".").first.map(String.init) ?? host
        let knownSites = [
            "youtube": "YouTube",
            "linkedin": "LinkedIn",
            "github": "GitHub",
            "chatgpt": "ChatGPT"
        ]

        return knownSites[baseName.lowercased()] ?? prettifiedName(baseName)
    }

    private func prettifiedName(_ value: String) -> String {
        let spaced = value
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )

        return spaced
            .split(separator: " ")
            .map { word in
                let text = String(word)
                if text.uppercased() == text { return text }
                return text.prefix(1).uppercased() + text.dropFirst()
            }
            .joined(separator: " ")
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
        case .runShortcut: "bolt.fill"
        }
    }
}
