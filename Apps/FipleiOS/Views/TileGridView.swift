import FipleKit
import SwiftUI
import UIKit

/// The remote's main screen: a grid of the Mac's tiles. Tap to run; the tile
/// shows progress and per-run feedback. No editing — this is a pure remote.
struct TileGridView: View {
    let controller: RemoteController

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if controller.tiles.isEmpty {
                    ContentUnavailableView(
                        "No tiles yet",
                        systemImage: "square.grid.2x2",
                        description: Text("Create tiles in the Fiple app on your Mac — they'll appear here.")
                    )
                    .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(controller.tiles) { tile in
                            TileButton(
                                tile: tile,
                                isRunning: controller.runningTileID == tile.id,
                                result: controller.runResults[tile.id]
                            ) {
                                Task { await controller.run(tile) }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(controller.macName ?? "Fiple")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            Task { await controller.disconnect() }
                        } label: {
                            Label("Disconnect", systemImage: "xmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

private struct TileButton: View {
    let tile: Tile
    let isRunning: Bool
    let result: RunResult?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    tileIcon
                    Spacer()
                    statusIcon
                }
                Spacer()
                Text(tile.name)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Text(tile.isWorkspace ? "\(tile.actions.count) actions" : "1 action")
                    .font(.caption)
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(height: 130, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: tile.colorHex), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
    }

    @ViewBuilder private var tileIcon: some View {
        if let data = tile.iconImageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: tile.iconSystemName)
                .font(.title2)
        }
    }

    @ViewBuilder private var statusIcon: some View {
        if isRunning {
            ProgressView().tint(.white)
        } else if let result {
            Image(systemName: result.allSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(result.allSucceeded ? .white : .yellow)
        }
    }
}
