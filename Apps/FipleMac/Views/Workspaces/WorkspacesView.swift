import FipleKit
import SwiftUI

/// The hero page: workspace cards plus Recent and Focus summaries.
struct WorkspacesView: View {
    let store: TileStore
    let server: ServerController
    let recents: RecentStore
    let pinned: PinnedAppsStore
    @Binding var section: SidebarSection

    private enum Layout: String { case grid, list }
    @State private var layout: Layout = .grid
    @State private var editingTile: Tile?
    @State private var isCreating = false
    @State private var deletingTile: Tile?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                PageHeader(
                    title: "Workspaces",
                    subtitle: "Create, organize and manage your work environments."
                ) {
                    DeviceChip(server: server)
                }

                controls

                if store.tiles.isEmpty {
                    emptyState
                } else {
                    workspaces
                }

                // Fiple Bar, Recent and Focus stay visible even with no
                // workspaces — only the workspaces area itself goes empty.
                PinnedAppsSection(
                    store: store,
                    bar: pinned,
                    onViewAll: { section = .apps }
                )
                summaries
            }
            .padding(Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.sm) // breathing room under traffic lights
            .pageColumn(maxWidth: 1180)
        }
        .sheet(item: $editingTile) { TileEditorView(store: store, tile: $0) }
        .sheet(isPresented: $isCreating) { TileEditorView(store: store, tile: nil) }
        .alert(
            "Delete workspace?",
            isPresented: Binding(get: { deletingTile != nil }, set: { if !$0 { deletingTile = nil } }),
            presenting: deletingTile
        ) { tile in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { store.delete(tile.id) }
        } message: { tile in
            Text("Delete “\(tile.name)”? This can't be undone.")
        }
    }

    private var controls: some View {
        HStack(spacing: Theme.Spacing.md) {
            Spacer()
            layoutToggle
            Button {
                isCreating = true
            } label: {
                Label("New Workspace", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .foregroundStyle(.white)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            }
            .buttonStyle(.plain)
        }
    }

    private var layoutToggle: some View {
        HStack(spacing: 2) {
            toggleButton(.grid, icon: "square.grid.2x2")
            toggleButton(.list, icon: "list.bullet")
        }
        .padding(3)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.Palette.hairline))
    }

    private func toggleButton(_ value: Layout, icon: String) -> some View {
        Button { layout = value } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(layout == value ? .primary : .secondary)
                .frame(width: 30, height: 24)
                .background(
                    layout == value
                        ? AnyShapeStyle(Color.primary.opacity(0.08))
                        : AnyShapeStyle(Color.clear),
                    in: RoundedRectangle(cornerRadius: 7)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var workspaces: some View {
        switch layout {
        case .grid:
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: Theme.Spacing.lg) {
                ForEach(store.tiles) { tile in
                    WorkspaceCard(
                        tile: tile,
                        onEdit: { editingTile = tile },
                        onDelete: { deletingTile = tile }
                    )
                }
            }
        case .list:
            VStack(spacing: Theme.Spacing.md) {
                ForEach(store.tiles) { tile in
                    WorkspaceListRow(
                        tile: tile,
                        onEdit: { editingTile = tile },
                        onDelete: { deletingTile = tile }
                    )
                }
            }
        }
    }

    private let gridColumns = [GridItem(.adaptive(minimum: 270), spacing: Theme.Spacing.lg)]

    private var summaries: some View {
        Panel(title: "Recent", icon: "clock", actionTitle: "View all") { section = .recent } content: {
            RecentList(records: Array(recents.records.prefix(4)), emptyHint: "No launches yet", onRun: runRecord)
        }
    }

    private func runRecord(_ record: RunRecord) {
        if let action = record.replayAction {
            Task { await server.run(action) }
        } else if let tile = store.tiles.first(where: { $0.id == record.tileID }) {
            Task { await server.run(tile) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("No workspaces yet")
                .font(.system(size: 17, weight: .semibold))
            Text("Create a workspace to launch apps, websites, and files from your iPhone.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("New Workspace") { isCreating = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .fipleCard()
    }
}

/// Compact row used by the Workspaces list layout.
private struct WorkspaceListRow: View {
    let tile: Tile
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            IconTile(iconImageData: tile.iconImageData, systemName: tile.iconSystemName, colorHex: tile.colorHex)
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.name).font(.system(size: 15, weight: .semibold))
                Text(tile.subtitle ?? "\(tile.actions.count) actions")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text("\(tile.appCount) apps · \(tile.websiteCount) sites")
                .font(.caption).foregroundStyle(.secondary)
            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: tile.colorHex))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Edit \(tile.name)")
            Menu {
                Button("Edit", action: onEdit)
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(Theme.Spacing.md)
        .fipleCard(cornerRadius: Theme.Radius.tile)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }
}
