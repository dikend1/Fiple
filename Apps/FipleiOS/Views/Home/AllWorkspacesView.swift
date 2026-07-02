import FipleKit
import SwiftUI

/// Every workspace preset on one screen — pushed from Home's "View all".
/// Reuses the same cards and the same run path as the Home carousel.
struct AllWorkspacesView: View {
    let controller: RemoteController

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 14),
        count: 2
    )

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(controller.workspaces) { tile in
                    WorkspaceCardView(
                        tile: tile,
                        isRunning: controller.runningTileID == tile.id
                    ) {
                        Task { await controller.run(tile) }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.md)
            // Clear the floating tab bar so the last row of cards stays tappable.
            .padding(.bottom, Theme.Spacing.tabBarClearance)
        }
        .background(Theme.Palette.background)
        .navigationTitle("Workspaces")
        .navigationBarTitleDisplayMode(.inline)
    }
}
