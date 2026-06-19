import FipleKit
import SwiftUI

/// The main window: a fixed dark sidebar plus a routed detail area. A custom
/// split (rather than NavigationSplitView) gives full control over the dark
/// brand sidebar and the footer pinned to the bottom, matching the design.
struct MainWindowView: View {
    let store: TileStore
    let server: ServerController
    let recents: RecentStore
    let focus: FocusStore

    @State private var section: SidebarSection = .workspaces

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(section: $section, server: server)
                .frame(width: 250)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Palette.windowBackground)
                // The content surfaces are intentionally light (matching the
                // reference), so resolve semantic colours in light appearance
                // even when the system is in dark mode.
                .environment(\.colorScheme, .light)
        }
        .frame(minWidth: 960, minHeight: 640)
        .ignoresSafeArea()
    }

    @ViewBuilder private var detail: some View {
        switch section {
        case .workspaces:
            WorkspacesView(store: store, server: server, recents: recents, focus: focus, section: $section)
        case .apps:
            ActionCatalogView(store: store, kind: .apps)
        case .websites:
            ActionCatalogView(store: store, kind: .websites)
        case .shortcuts:
            ActionCatalogView(store: store, kind: .shortcuts)
        case .recent:
            RecentView(recents: recents)
        case .focus:
            FocusView(focus: focus)
        case .devices:
            DevicesView(server: server)
        case .settings:
            SettingsView(server: server)
        }
    }
}
