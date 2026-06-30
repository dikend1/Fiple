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

    /// Current page of the paged Fiple Bar (8 tiles per page).
    @State private var fipleBarPage = 0

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
                // Clear the floating tab bar so the last section (the Fiple Bar's
                // bottom row of tiles) can scroll fully into view above it.
                .padding(.bottom, 96)
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
                                isRunning: controller.runningTileID == tile.id,
                                isLocked: controller.lockedWorkspaceIDs.contains(tile.id)
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
        let raw = controller.fipleBar
        if !raw.isEmpty {
            // Free actions first, locked (Pro) ones pushed to the end so the paid
            // tiles land on the later pages — page through with the arrows or by
            // swiping; 8 tiles (4×2) per page.
            let free = raw.filter { !controller.lockedFipleBarActionIDs.contains($0.id) }
            let locked = raw.filter { controller.lockedFipleBarActionIDs.contains($0.id) }
            let pages = (free + locked).chunked(into: 8)
            let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md), count: 4)
            // Every page is padded with empty slots to a full 4×2, so the height
            // is always two rows of tiles.
            let gridHeight = CGFloat(2) * 120 + Theme.Spacing.md

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "Fiple Bar") {
                    if pages.count > 1 {
                        HStack(spacing: Theme.Spacing.sm) {
                            pageArrow("chevron.left", enabled: fipleBarPage > 0) { fipleBarPage -= 1 }
                            pageArrow("chevron.right", enabled: fipleBarPage < pages.count - 1) { fipleBarPage += 1 }
                        }
                    }
                }

                TabView(selection: $fipleBarPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                            ForEach(page) { action in
                                Button {
                                    Task { await controller.runAction(action) }
                                } label: {
                                    QuickAccessTile(
                                        item: QuickAction(action: action, tileID: action.id),
                                        isRunning: controller.runningActionID == action.id,
                                        isLocked: controller.lockedFipleBarActionIDs.contains(action.id)
                                    )
                                }
                                .buttonStyle(QuickTilePressStyle())
                            }
                            // Pad the page out to a full 4×2 with empty ghost slots.
                            ForEach(0 ..< max(0, 8 - page.count), id: \.self) { _ in
                                QuickAccessSlot()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: gridHeight)
                .animation(.easeInOut, value: fipleBarPage)
            }
        }
    }

    /// A circular ‹ / › control for paging the Fiple Bar; dims and disables at the ends.
    private func pageArrow(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut) { action() }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? Theme.Palette.label : Theme.Palette.secondary.opacity(0.4))
                .frame(width: 30, height: 30)
                .background(Theme.Palette.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.Palette.hairline))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// Runs the parent tile of a quick-access action (the wire protocol triggers
    /// whole tiles, not individual actions).
    private func run(_ item: QuickAction) {
        guard let tile = controller.tiles.first(where: { $0.id == item.tileID }) else { return }
        Task { await controller.run(tile) }
    }
}

private extension Array {
    /// Splits the array into consecutive chunks of at most `size` elements.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
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
