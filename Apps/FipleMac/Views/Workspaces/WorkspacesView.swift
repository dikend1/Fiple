import FipleKit
import SwiftUI

/// The hero page: workspace cards plus Recent and Focus summaries.
struct WorkspacesView: View {
    let store: TileStore
    let server: ServerController
    let recents: RecentStore
    let focus: FocusStore
    @Binding var section: SidebarSection

    private enum Layout: String { case grid, list }
    @State private var layout: Layout = .grid
    @State private var editingTile: Tile?
    @State private var isCreating = false

    private let columns = [GridItem(.flexible(), spacing: Theme.Spacing.xl),
                           GridItem(.flexible(), spacing: Theme.Spacing.xl)]

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
                    summaries
                }
            }
            .padding(Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.sm) // breathing room under traffic lights
        }
        .sheet(item: $editingTile) { TileEditorView(store: store, tile: $0) }
        .sheet(isPresented: $isCreating) { TileEditorView(store: store, tile: nil) }
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
            LazyVGrid(columns: columns, spacing: Theme.Spacing.xl) {
                ForEach(store.tiles) { tile in
                    WorkspaceCard(
                        tile: tile,
                        onEdit: { editingTile = tile },
                        onDelete: { store.delete(tile.id) }
                    )
                }
            }
        case .list:
            VStack(spacing: Theme.Spacing.md) {
                ForEach(store.tiles) { tile in
                    WorkspaceListRow(
                        tile: tile,
                        onEdit: { editingTile = tile },
                        onDelete: { store.delete(tile.id) }
                    )
                }
            }
        }
    }

    private var summaries: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            Panel(title: "Recent", icon: "clock", actionTitle: "View all") { section = .recent } content: {
                RecentList(records: Array(recents.records.prefix(4)), emptyHint: "No launches yet")
            }
            Panel(title: "Focus", icon: "target", actionTitle: "View all") { section = .focus } content: {
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(focus.modes.prefix(4)) { mode in
                        FocusToggleRow(mode: mode) { focus.toggle(mode.id) }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No workspaces yet", systemImage: "square.grid.2x2")
        } description: {
            Text("Create a workspace to launch apps, websites, and files from your iPhone.")
        } actions: {
            Button("New Workspace") { isCreating = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
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
            Text("\(tile.appCount) apps · \(tile.websiteCount) sites · \(tile.shortcutCount) files")
                .font(.caption).foregroundStyle(.secondary)
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
