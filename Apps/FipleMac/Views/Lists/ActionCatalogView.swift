import FipleKit
import SwiftUI

/// Lists every action of one kind across all workspaces (the Apps / Websites /
/// Shortcuts sidebar pages). A read-only catalogue — editing happens on the tile.
struct ActionCatalogView: View {
    let store: TileStore
    let kind: Kind

    enum Kind {
        case apps, websites, shortcuts

        var title: String {
            switch self {
            case .apps: "Apps"
            case .websites: "Websites"
            case .shortcuts: "Shortcuts"
            }
        }
        var subtitle: String {
            switch self {
            case .apps: "Applications launched by your workspaces."
            case .websites: "Websites opened by your workspaces."
            case .shortcuts: "Files and folders opened by your workspaces."
            }
        }
        var icon: String {
            switch self {
            case .apps: "shippingbox"
            case .websites: "globe"
            case .shortcuts: "bolt"
            }
        }
        var color: String {
            switch self {
            case .apps: "#84CC16"
            case .websites: "#0EA5E9"
            case .shortcuts: "#F59E0B"
            }
        }
    }

    private struct Entry: Identifiable {
        let id: UUID
        let title: String
        let workspace: String
        let icon: String
        let color: String
    }

    private var entries: [Entry] {
        store.tiles.flatMap { tile in
            tile.actions.compactMap { action -> Entry? in
                guard let title = label(for: action.kind) else { return nil }
                return Entry(id: action.id, title: title, workspace: tile.name, icon: kind.icon, color: kind.color)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                PageHeader(title: kind.title, subtitle: kind.subtitle)

                if entries.isEmpty {
                    ContentUnavailableView(
                        "No \(kind.title.lowercased()) yet",
                        systemImage: kind.icon,
                        description: Text("Add a \(kind.title.dropLast().lowercased()) action to a workspace.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            row(entry)
                            if entry.id != entries.last?.id { Divider().padding(.leading, 44) }
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .fipleCard()
                }
            }
            .padding(Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.sm)
        }
    }

    private func row(_ entry: Entry) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            IconTile(iconImageData: nil, systemName: entry.icon, colorHex: entry.color, size: 32, cornerRadius: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(entry.workspace).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    /// Returns a friendly label only for actions matching this page's kind.
    private func label(for kind: ActionKind) -> String? {
        switch (self.kind, kind) {
        case let (.apps, .launchApp(bundleID)):
            return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        case let (.websites, .openURL(url)):
            return url.host() ?? url.absoluteString
        case let (.shortcuts, .openFile(path, _)):
            return (path as NSString).lastPathComponent
        default:
            return nil
        }
    }
}
