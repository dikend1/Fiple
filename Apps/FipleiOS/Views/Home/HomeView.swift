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

                    quickLaunch

                    quickAccess
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.tabBarClearance)
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
                .font(.fiple(34, .bold))
                .foregroundStyle(Theme.Palette.label)
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.fiple(18, .semibold))
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
                    NavigationLink {
                        AllWorkspacesView(controller: controller)
                    } label: {
                        Text("View all")
                            .font(.fiple(15, .semibold))
                            .foregroundStyle(Theme.Palette.brandLink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View all workspaces")
                }
            }

            if items.isEmpty {
                EmptyHint(
                    icon: "square.grid.2x2",
                    text: controller.phase == .connected
                        ? "Create workspaces in the Fiple app on your Mac — they'll appear here."
                        : "Workspaces appear when your iPhone and Mac are on the same Wi-Fi."
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

    // MARK: Quick Launch

    /// Single-action tiles (everything that isn't a workspace preset) — without
    /// this section they'd exist on the Mac but be unreachable from the phone.
    /// May overlap with the Fiple Bar below; acceptable for v1.
    @ViewBuilder private var quickLaunch: some View {
        let items = controller.tiles.filter { !$0.isWorkspace && !$0.actions.isEmpty }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader("Quick Launch")

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md), count: 4),
                    spacing: Theme.Spacing.md
                ) {
                    ForEach(items) { tile in
                        if let action = tile.actions.first {
                            Button {
                                Task { await controller.run(tile) }
                            } label: {
                                QuickAccessTile(
                                    item: QuickAction(action: action, tileID: tile.id),
                                    isRunning: controller.runningTileID == tile.id
                                )
                            }
                            .buttonStyle(QuickTilePressStyle())
                        }
                    }
                }
            }
        }
    }

    // MARK: Quick Access

    @ViewBuilder private var quickAccess: some View {
        let items = controller.fipleBar
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader("Fiple Bar")

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md), count: 4),
                    spacing: Theme.Spacing.md
                ) {
                    ForEach(items) { action in
                        Button {
                            Task { await controller.runAction(action) }
                        } label: {
                            QuickAccessTile(
                                item: QuickAction(action: action, tileID: action.id),
                                isRunning: controller.runningActionID == action.id
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
                .font(.fiple(26))
                .foregroundStyle(Theme.Palette.secondary)
            Text(text)
                .font(.fiple(14))
                .foregroundStyle(Theme.Palette.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .fipleCard()
    }
}
