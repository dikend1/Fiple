import FipleKit
import SwiftUI

/// Mac-only tile management: create, edit, reorder, delete. The phone is a pure
/// remote and never edits (see PRD `fiple-remote-tiles`).
struct TileManagerView: View {
    @Bindable var store: TileStore
    let server: ServerController

    @State private var editingTile: Tile?
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.tiles.isEmpty {
                ContentUnavailableView(
                    "No tiles yet",
                    systemImage: "square.grid.2x2",
                    description: Text("Create a tile to launch apps, URLs, or files from your iPhone.")
                )
            } else {
                List {
                    ForEach(store.tiles) { tile in
                        TileRow(tile: tile)
                            .contentShape(Rectangle())
                            .onTapGesture { editingTile = tile }
                    }
                    .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { offsets in
                        offsets.map { store.tiles[$0].id }.forEach(store.delete)
                    }
                }
            }
        }
        .sheet(item: $editingTile) { tile in
            TileEditorView(store: store, tile: tile)
        }
        .sheet(isPresented: $isCreating) {
            TileEditorView(store: store, tile: nil)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Tiles").font(.title2).bold()
                Text(connectionSubtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { isCreating = true } label: {
                Label("Add Tile", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var connectionSubtitle: String {
        switch server.status {
        case .connected: "iPhone connected — changes sync live"
        case .advertising: "Waiting for iPhone • code \(server.pairingCode?.value ?? "----")"
        case .idle: "Starting…"
        }
    }
}

private struct TileRow: View {
    let tile: Tile

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(hex: tile.colorHex))
                .frame(width: 38, height: 38)
                .overlay(Image(systemName: tile.iconSystemName).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.name).font(.body.weight(.medium))
                Text(tile.isWorkspace ? "\(tile.actions.count) actions" : actionSummary)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var actionSummary: String {
        tile.actions.first?.displayLabel ?? "No actions"
    }
}
