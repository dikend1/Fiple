import FipleKit
import SwiftUI

/// Recent: the remote's launch history (recorded on this phone), filterable by
/// type. Tap a row to relaunch its workspace on the Mac.
struct RecentView: View {
    let controller: RemoteController

    @State private var filter: Filter = .all
    /// Transient "connect to relaunch" hint shown when a row is tapped while the
    /// Mac isn't reachable (relaunching needs a live LAN connection).
    @State private var showConnectHint = false
    @State private var hintDismissTask: Task<Void, Never>?

    private var connected: Bool { controller.phase == .connected }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case apps = "Apps"
        case websites = "Websites"
        case shortcuts = "Shortcuts"
        case workspaces = "Workspaces"
        var id: String { rawValue }

        var category: LaunchRecord.Category? {
            switch self {
            case .all: nil
            case .apps: .app
            case .websites: .website
            case .shortcuts: .shortcut
            case .workspaces: .workspace
            }
        }
    }

    private var items: [LaunchRecord] {
        guard let category = filter.category else { return controller.recents }
        return controller.recents.filter { $0.category == category }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    filterBar

                    if controller.recents.isEmpty {
                        EmptyHint(
                            icon: "clock",
                            text: "Launch a workspace or app and it'll show up here."
                        )
                    } else if items.isEmpty {
                        EmptyHint(icon: "line.3.horizontal.decrease", text: "Nothing in this filter yet.")
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                Button {
                                    run(item)
                                } label: {
                                    RecentRow(item: item)
                                }
                                .buttonStyle(.plain)
                                // Not connected → the row can't relaunch; look
                                // disabled but stay tappable so the tap explains
                                // itself instead of silently doing nothing.
                                .opacity(connected ? 1 : 0.45)
                                .accessibilityHint(connected ? "" : "Unavailable. Connect to your Mac on the same Wi-Fi to relaunch.")
                                if index < items.count - 1 {
                                    Divider().padding(.leading, 72)
                                }
                            }
                        }
                        .fipleCard()
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.tabBarClearance)
            }
            .background(Theme.Palette.background)
            .overlay(alignment: .bottom) {
                if showConnectHint {
                    connectHint
                }
            }
            .navigationTitle("Recent")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !controller.recents.isEmpty {
                        Menu {
                            Button("Clear History", role: .destructive) { controller.clearRecents() }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.fiple(16, .semibold))
                                .foregroundStyle(Theme.Palette.label)
                                .frame(width: 38, height: 38)
                                .fipleCard(cornerRadius: Theme.Radius.control)
                        }
                        .accessibilityLabel("History options")
                    }
                }
            }
        }
    }

    private func run(_ item: LaunchRecord) {
        // Relaunching needs the live connection — off-network, explain instead
        // of a silent no-op (RemoteController guards internally too).
        guard connected else {
            presentConnectHint()
            return
        }
        // Single-action launches re-dispatch the action itself; workspace
        // launches look up the tile by id.
        if let action = item.replayAction {
            Task { await controller.runAction(action) }
        } else if let tile = controller.tiles.first(where: { $0.id == item.tileID }) {
            Task { await controller.run(tile) }
        }
    }

    // MARK: Connect hint

    /// A soft transient toast above the tab bar; auto-dismisses after a moment.
    private var connectHint: some View {
        Text("Connect to your Mac on the same Wi-Fi to relaunch")
            .font(.fiple(13, .semibold))
            .foregroundStyle(Theme.Palette.label)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Palette.hairline))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
            .padding(.horizontal, Theme.Spacing.lg)
            // Float clear of the floating tab bar, not behind it.
            .padding(.bottom, Theme.Spacing.tabBarClearance)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityAddTraits(.updatesFrequently)
    }

    private func presentConnectHint() {
        hintDismissTask?.cancel()
        withAnimation(.snappy(duration: 0.25)) { showConnectHint = true }
        hintDismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { showConnectHint = false }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(Filter.allCases) { option in
                    let selected = option == filter
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { filter = option }
                    } label: {
                        Text(option.rawValue)
                            .font(.fiple(15, .semibold))
                            .foregroundStyle(selected ? Theme.Palette.brand : Theme.Palette.secondary)
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.vertical, Theme.Spacing.sm + 2)
                            .background(
                                Capsule().fill(selected ? Theme.Palette.brand.opacity(0.14) : Color.black.opacity(0.04))
                            )
                            .overlay(
                                Capsule().strokeBorder(selected ? Theme.Palette.brand.opacity(0.5) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

/// One launch-history row: real tile icon, name, type, time, chevron.
private struct RecentRow: View {
    let item: LaunchRecord

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            if item.iconImageData == nil, let host = item.faviconHost {
                Favicon(host: host, size: 44, cornerRadius: 12)
            } else {
                TileIcon(
                    iconImageData: item.iconImageData,
                    systemName: item.iconSystemName,
                    colorHex: item.colorHex,
                    size: 44,
                    cornerRadius: 12
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.fiple(16, .semibold))
                    .foregroundStyle(Theme.Palette.label)
                Text(item.categoryLabel)
                    .font(.fiple(13))
                    .foregroundStyle(Theme.Palette.secondary)
            }

            Spacer()

            Text(item.displayTime)
                .font(.fiple(14))
                .foregroundStyle(Theme.Palette.secondary)
            Image(systemName: "chevron.right")
                .font(.fiple(13, .semibold))
                .foregroundStyle(Theme.Palette.secondary.opacity(0.6))
        }
        .padding(Theme.Spacing.md)
        .contentShape(Rectangle())
    }
}
