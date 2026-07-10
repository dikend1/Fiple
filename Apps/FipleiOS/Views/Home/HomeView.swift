import FipleKit
import SwiftUI

/// Home: the connected-Mac status card, the real workspace presets (2+ actions)
/// streamed from the Mac, and the Fiple Bar grid of single apps / sites pinned
/// for one-tap launch. Tapping a card or icon runs it on the Mac.
struct HomeView: View {
    let controller: RemoteController
    /// Switches the tab bar to Settings — wired to the gear in the header so it
    /// matches the mockup without nesting a second settings navigation stack.
    var onOpenSettings: () -> Void = {}


    var body: some View {
        NavigationStack {
            #if DEBUG
            // "-demo-trash" (with -demo): open straight into the review screen,
            // for previews/screenshots without tapping through.
            if ProcessInfo.processInfo.arguments.contains("-demo-trash") {
                TrashReviewView(controller: controller)
            } else {
                homeContent
            }
            #else
            homeContent
            #endif
        }
    }

    private var homeContent: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    header

                    ConnectionCard(controller: controller)


                    workspaces

                    quickAccess
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.tabBarClearance)
            }
            .background(Theme.Palette.background)
            .toolbar(.hidden, for: .navigationBar)
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
            // No "View all" — the carousel below already scrolls through every
            // workspace, so a separate grid screen was a redundant extra tap.
            SectionHeader("Workspaces")

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
                     ? "Apps and websites you add to the Fiple Bar on your Mac appear here."
                     : "Connect to your Mac on the same Wi-Fi to see your Fiple Bar apps and websites.")
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

}

/// Height of one icon tile (icon + label + padding), so empty placeholder slots
/// line up exactly with real tiles when a page is padded out.
private let tileSlotHeight: CGFloat = 120

/// Lays icon tiles out **eight per page** (4×2) and pages horizontally, exactly
/// like the Mac's Fiple Bar: the last page is padded with empty slots so every
/// page is a full grid, and a row of page dots appears once there's more than
/// one page. This keeps the section a fixed two rows tall no matter how many
/// items there are.
private struct PagedTileGrid<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    @ViewBuilder let tile: (Item) -> Tile

    @State private var currentPage: Int?

    private let perPage = 8
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.md),
        count: 4
    )

    /// Items split into pages of eight, preserving order (row-major per page).
    private var pages: [[Item]] {
        stride(from: 0, to: items.count, by: perPage).map {
            Array(items[$0 ..< min($0 + perPage, items.count)])
        }
    }

    var body: some View {
        let pages = pages

        VStack(spacing: Theme.Spacing.md) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                            ForEach(page) { item in tile(item) }
                            // Pad the last page with empty slots so every page is
                            // a full 4×2 grid, matching the Mac's Fiple Bar.
                            ForEach(0 ..< (perPage - page.count), id: \.self) { _ in
                                PlaceholderSlot()
                            }
                        }
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
/// same 4×2 shape a full page uses, so the area reads as "apps go here" (like
/// the Mac's Fiple Bar) rather than collapsing into blank white space.
private struct PlaceholderTileGrid: View {
    var count = 8

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.md),
        count: 4
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
            ForEach(0 ..< count, id: \.self) { _ in PlaceholderSlot() }
        }
        .accessibilityHidden(true)
    }
}

/// A single empty Fiple Bar slot: a plain soft well the same size as a tile,
/// matching the Mac's empty slots — no icon, just a subtle filled card.
private struct PlaceholderSlot: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Theme.Palette.secondary.opacity(0.05))
            .frame(height: tileSlotHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline)
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
