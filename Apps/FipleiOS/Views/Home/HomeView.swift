import FipleKit
import SwiftUI

/// Home: the connected-Mac status card, the real workspace presets streamed from
/// the Mac, and a Quick Access grid of the individual apps / sites / files those
/// workspaces use. Tapping a card or icon runs it on the Mac.
struct HomeView: View {
    let controller: RemoteController
    /// Switches the tab bar to Settings — wired to the gear in the header so it
    /// matches the mockup without nesting a second settings navigation stack.
    var onOpenSettings: () -> Void = {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    header

                    ConnectionCard(controller: controller)

                    workspaces

                    quickAccess
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background(Theme.Palette.background)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Header

    /// The large "Fiple" wordmark with the settings gear on the same row, matching
    /// the mockup — a custom header rather than a large nav title so the gear sits
    /// beside the title instead of above it.
    private var header: some View {
        HStack(alignment: .center) {
            Text("Fiple")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.Palette.label)
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Palette.secondary)
                    .frame(width: 40, height: 40)
                    .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.Palette.hairline))
            }
            .accessibilityLabel("Settings")
        }
    }

    // MARK: Workspaces

    @ViewBuilder private var workspaces: some View {
        let items = controller.workspaces
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Workspaces") {
                if !items.isEmpty {
                    Text("View all")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.brandLink)
                }
            }

            if items.isEmpty {
                EmptyHint(
                    icon: "square.grid.2x2",
                    text: "Create workspaces in the Fiple app on your Mac — they'll appear here."
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.md) {
                        ForEach(items) { tile in
                            WorkspaceCardView(
                                tile: tile,
                                isRunning: controller.runningTileID == tile.id
                            ) {
                                Task { await controller.run(tile) }
                            }
                            .frame(width: 200)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    // MARK: Quick Access

    @ViewBuilder private var quickAccess: some View {
        let items = controller.quickAccess
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader("Quick Access")

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md), count: 4),
                    spacing: Theme.Spacing.md
                ) {
                    ForEach(items) { item in
                        Button {
                            run(item)
                        } label: {
                            QuickAccessTile(
                                item: item,
                                isRunning: controller.runningTileID == item.tileID
                            )
                        }
                        .buttonStyle(QuickTilePressStyle())
                    }
                }
            }
        }
    }

    /// Runs the parent tile of a quick-access action (the wire protocol triggers
    /// whole tiles, not individual actions).
    private func run(_ item: QuickAction) {
        guard let tile = controller.tiles.first(where: { $0.id == item.tileID }) else { return }
        Task { await controller.run(tile) }
    }
}

/// A soft empty-state hint shown inside a section.
struct EmptyHint: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(Theme.Palette.secondary)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .fipleCard()
    }
}
