import FipleKit
import SwiftUI

/// Recent: the remote's launch history (recorded on this phone), filterable by
/// type. Tap a row to relaunch its workspace on the Mac.
struct RecentView: View {
    let controller: RemoteController

    @State private var filter: Filter = .all

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
                                if index < items.count - 1 {
                                    Divider().padding(.leading, 72)
                                }
                            }
                        }
                        .fipleCard()
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background(Theme.Palette.background)
            .navigationTitle("Recent")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !controller.recents.isEmpty {
                        Menu {
                            Button("Clear History", role: .destructive) { controller.clearRecents() }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 16, weight: .semibold))
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
        // Single-action launches re-dispatch the action itself; workspace
        // launches look up the tile by id.
        if let action = item.replayAction {
            Task { await controller.runAction(action) }
        } else if let tile = controller.tiles.first(where: { $0.id == item.tileID }) {
            Task { await controller.run(tile) }
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
                            .font(.system(size: 15, weight: .semibold))
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Palette.label)
                Text(item.categoryLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.secondary)
            }

            Spacer()

            Text(item.displayTime)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.secondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.secondary.opacity(0.6))
        }
        .padding(Theme.Spacing.md)
        .contentShape(Rectangle())
    }
}
