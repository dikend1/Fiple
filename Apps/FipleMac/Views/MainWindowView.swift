import FipleKit
import SwiftUI

/// The main window: a fixed dark sidebar plus a routed detail area. A custom
/// split (rather than NavigationSplitView) gives full control over the dark
/// brand sidebar and the footer pinned to the bottom, matching the design.
struct MainWindowView: View {
    let store: TileStore
    let server: ServerController
    let recents: RecentStore
    let pinned: PinnedAppsStore

    @State private var section: SidebarSection = .workspaces
    @State private var sidebarVisible = true

    private let sidebarWidth: CGFloat = 250

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                SidebarView(section: $section, server: server)
                    .frame(width: sidebarWidth)
                    .transition(.move(edge: .leading))
            }

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Palette.windowBackground)
                // The content surfaces are intentionally light (matching the
                // reference), so resolve semantic colours in light appearance
                // even when the system is in dark mode.
                .environment(\.colorScheme, .light)
                // The page header renders a sidebar toggle from this action, so
                // every page gets a consistent, well-placed control and ⌃⌘S.
                .environment(\.toggleSidebar, SidebarToggle(isOpen: sidebarVisible) {
                    sidebarVisible.toggle()
                })
        }
        .frame(minWidth: 720, minHeight: 640)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.22), value: sidebarVisible)
    }

    /// Re-run a Recent entry: re-dispatch a single action, or look up the
    /// workspace tile by id against the current tiles.
    private func run(record: RunRecord) {
        if let action = record.replayAction {
            Task { await server.run(action) }
        } else if let tile = store.tiles.first(where: { $0.id == record.tileID }) {
            Task { await server.run(tile) }
        }
    }

    @ViewBuilder private var detail: some View {
        switch section {
        case .workspaces:
            WorkspacesView(store: store, server: server, recents: recents, pinned: pinned, section: $section)
        case .apps:
            ActionCatalogView(store: store, pinned: pinned, kind: .apps)
        case .websites:
            ActionCatalogView(store: store, pinned: pinned, kind: .websites)
        case .recent:
            RecentView(recents: recents, onRun: run(record:))
        case .terminal:
            TerminalToolView(server: server)
        case .smartTrash:
            SmartTrashToolView(server: server)
        case .devices:
            DevicesView(server: server)
        case .settings:
            SettingsView(server: server)
        }
    }
}

/// The sidebar-collapse action, passed via the environment so any page's header
/// can render the toggle in a consistent place.
struct SidebarToggle: @unchecked Sendable {
    let isOpen: Bool
    let action: () -> Void
}

private struct SidebarToggleKey: EnvironmentKey {
    static let defaultValue: SidebarToggle? = nil
}

extension EnvironmentValues {
    var toggleSidebar: SidebarToggle? {
        get { self[SidebarToggleKey.self] }
        set { self[SidebarToggleKey.self] = newValue }
    }
}
