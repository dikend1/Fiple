import AppKit
import FipleKit
import SwiftUI

/// Lists every action of one kind across all workspaces (the Apps / Websites /
/// Shortcuts sidebar pages). A read-only catalogue — editing happens on the tile.
struct ActionCatalogView: View {
    let store: TileStore
    let pinned: PinnedAppsStore
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

    @State private var hoveredID: UUID?
    @State private var deleteHoverID: UUID?
    @State private var pendingRemoval: Entry?

    private struct Entry: Identifiable {
        let id: UUID
        /// Parent workspace, or nil when the entry comes from the Fiple Bar.
        let tileID: UUID?
        let kind: ActionKind
        let title: String
        let source: String
    }

    /// Actions of this kind across all workspaces *and* the Fiple Bar.
    private var entries: [Entry] {
        var result: [Entry] = []
        for tile in store.tiles {
            for action in tile.actions {
                guard let title = label(for: action.kind) else { continue }
                result.append(Entry(id: action.id, tileID: tile.id, kind: action.kind, title: title, source: tile.name))
            }
        }
        for action in pinned.actions {
            guard let title = label(for: action.kind) else { continue }
            result.append(Entry(id: action.id, tileID: nil, kind: action.kind, title: title, source: "Fiple Bar"))
        }
        return result
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
        .alert(
            "Remove this action?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { entry in
            Button("Remove", role: .destructive) { remove(entry) }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text("“\(entry.title)” will be removed from “\(entry.source)”.")
        }
    }

    private func row(_ entry: Entry) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            icon(for: entry.kind)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(entry.source).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if hoveredID == entry.id {
                Button { pendingRemoval = entry } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: deleteHoverID == entry.id ? .semibold : .regular))
                        .foregroundStyle(deleteHoverID == entry.id ? Color.red : .secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            deleteHoverID == entry.id ? Color.red.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove from \(entry.source)")
                .onHover { deleteHoverID = $0 ? entry.id : (deleteHoverID == entry.id ? nil : deleteHoverID) }
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .contentShape(Rectangle())
        .onHover { hoveredID = $0 ? entry.id : (hoveredID == entry.id ? nil : hoveredID) }
        .contextMenu {
            Button("Remove from \(entry.source)", role: .destructive) { pendingRemoval = entry }
        }
    }

    /// Removes this action from its parent workspace (the catalogue's source of
    /// truth). The list updates automatically as the store is observed.
    private func remove(_ entry: Entry) {
        if let tileID = entry.tileID {
            guard var tile = store.tiles.first(where: { $0.id == tileID }) else { return }
            tile.actions.removeAll { $0.id == entry.id }
            store.update(tile)
        } else {
            pinned.remove(entry.id)
        }
    }

    /// A real icon for the action: the app's icon, the site favicon, or the
    /// Finder icon of the file/folder.
    @ViewBuilder private func icon(for kind: ActionKind) -> some View {
        switch kind {
        case let .launchApp(bundleID):
            NativeIconTile(image: SystemIcon.app(bundleID: bundleID), fallbackSymbol: "app.dashed")
        case let .openURL(url):
            FaviconView(host: url.host() ?? "")
        case let .openFile(path, _):
            NativeIconTile(image: SystemIcon.file(path: path), fallbackSymbol: "folder")
        }
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
