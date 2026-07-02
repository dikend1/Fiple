import FipleKit
import SwiftUI

/// Every workspace preset on one screen — pushed from Home's "View all".
/// Reuses the same cards and the same run path as the Home carousel.
struct AllWorkspacesView: View {
    let controller: RemoteController

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.md),
        count: 2
    )

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                ForEach(controller.workspaces) { tile in
                    WorkspaceCardView(
                        tile: tile,
                        isRunning: controller.runningTileID == tile.id
                    ) {
                        Task { await controller.run(tile) }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Theme.Palette.background)
        .navigationTitle("Workspaces")
        .navigationBarTitleDisplayMode(.inline)
    }
}
