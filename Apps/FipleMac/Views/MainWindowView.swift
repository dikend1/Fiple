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

    /// One-time welcome sheet on first launch.
    @AppStorage("fiple.hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false
    /// Which copy the welcome tells on its tools page; the DEBUG Settings row
    /// replays the welcome with the Mac App Store copy for preview.
    @State private var welcomeTerminalAvailable = TerminalController.isFeatureAvailable

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
        .sheet(isPresented: $showWelcome) {
            WelcomeSheet(onFinish: {
                hasSeenWelcome = true
                showWelcome = false
            }, terminalAvailable: welcomeTerminalAvailable)
            // Content pages resolve in light appearance; keep the sheet in step.
            .environment(\.colorScheme, .light)
        }
        .onAppear {
            #if DEBUG
            // "-welcome": force the first-run welcome, for screenshots.
            if ProcessInfo.processInfo.arguments.contains("-welcome") { showWelcome = true }
            #endif
            // Zip download running from ~/Downloads? Offer to move to
            // /Applications first — the welcome then shows from the real home.
            SelfInstaller.offerMoveToApplicationsIfNeeded()
            if !hasSeenWelcome { showWelcome = true }
        }
        // Settings → Show Welcome Guide re-opens the onboarding on demand; the
        // DEBUG row passes terminalAvailable=false to preview the MAS copy.
        .onReceive(NotificationCenter.default.publisher(for: .fipleReplayWelcome)) { note in
            welcomeTerminalAvailable =
                (note.userInfo?["terminalAvailable"] as? Bool) ?? TerminalController.isFeatureAvailable
            showWelcome = true
        }
        // Welcome's final CTA: land on Workspaces (its view opens the editor).
        .onReceive(NotificationCenter.default.publisher(for: .fipleCreateFirstWorkspace)) { _ in
            section = .workspaces
        }
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
