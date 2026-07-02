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

                PagedTileGrid(items: items) { tile in
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

    // MARK: Quick Access

    @ViewBuilder private var quickAccess: some View {
        let items = controller.fipleBar
        // The section is always present — when there's nothing yet it shows a
        // grid of empty slots (like the Mac's Fiple Bar) instead of collapsing
        // to a blank area, so the user can see where their apps will live.
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader("Fiple Bar")

            if items.isEmpty {
                PlaceholderTileGrid()
                Text(controller.phase == .connected
                     ? "Apps, websites and shortcuts you add to the Fiple Bar on your Mac appear here."
                     : "Connect to your Mac on the same Wi-Fi to see your Fiple Bar apps, websites and shortcuts.")
                    .font(.fiple(13))
                    .foregroundStyle(Theme.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                PagedTileGrid(items: items) { action in
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

    /// Runs the parent tile of a quick-access action (the wire protocol triggers
    /// whole tiles, not individual actions).
    private func run(_ item: QuickAction) {
        guard let tile = controller.tiles.first(where: { $0.id == item.tileID }) else { return }
        Task { await controller.run(tile) }
    }
}

/// Lays icon tiles out four-across, **two rows per page**, and pages
/// horizontally when there are more than eight — so a section with many items
/// never grows past two rows; the rest are a swipe to the right, like the iOS
/// Home Screen. A row of page dots appears once there's more than one page.
private struct PagedTileGrid<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    @ViewBuilder let tile: (Item) -> Tile

    @State private var currentPage: Int?

    private let columnCount = 4
    private let rowsPerPage = 2

    /// Items split into pages of `columnCount * rowsPerPage`, preserving order
    /// (row-major within each page).
    private var pages: [[Item]] {
        let perPage = columnCount * rowsPerPage
        return stride(from: 0, to: items.count, by: perPage).map {
            Array(items[$0 ..< min($0 + perPage, items.count)])
        }
    }

    var body: some View {
        let pages = pages
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: Theme.Spacing.md),
            count: columnCount
        )

        VStack(spacing: Theme.Spacing.md) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, chunk in
                        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.md) {
                            ForEach(chunk) { item in tile(item) }
                        }
                        // Each page is exactly the width of the scroll area so
                        // the paging snaps cleanly to a full 2×4 grid.
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentPage)
            .scrollIndicators(.hidden)
            .scrollDisabled(pages.count <= 1)

            if pages.count > 1 {
                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { i in
                        Circle()
                            .fill((currentPage ?? 0) == i ? Theme.Palette.brand : Theme.Palette.secondary.opacity(0.25))
                            .frame(width: 7, height: 7)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: currentPage)
                .accessibilityHidden(true)
            }
        }
    }
}

/// The empty-state for an icon section: a grid of soft dashed "slots" in the
/// same 2×4 shape a full page uses, so the area reads as "apps go here" (like
/// the Mac's Fiple Bar) rather than collapsing into blank white space.
private struct PlaceholderTileGrid: View {
    var count = 8

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.md),
        count: 4
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
            ForEach(0 ..< count, id: \.self) { _ in slot }
        }
        .accessibilityHidden(true)
    }

    private var slot: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Theme.Palette.secondary.opacity(0.05))
            .frame(height: 96)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        Theme.Palette.hairline,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
            .overlay(
                Image(systemName: "app.dashed")
                    .font(.fiple(22))
                    .foregroundStyle(Theme.Palette.secondary.opacity(0.35))
            )
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
