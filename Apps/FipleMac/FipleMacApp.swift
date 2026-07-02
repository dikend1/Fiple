import AppKit
import FipleKit
import SwiftUI

@main
struct FipleMacApp: App {
    @State private var store: TileStore
    @State private var server: ServerController
    @State private var recents: RecentStore
    @State private var pinned: PinnedAppsStore

    init() {
        let store = TileStore()
        let recents = RecentStore()
        let pinned = PinnedAppsStore()
        let server = ServerController(store: store, pinned: pinned)
        _store = State(initialValue: store)
        _server = State(initialValue: server)
        _recents = State(initialValue: recents)
        _pinned = State(initialValue: pinned)
        // Wire launch history and start advertising on the main actor. Done in a
        // Task because App.init is nonisolated while these touch @MainActor state.
        Task { @MainActor in
            server.didRun = { tile in recents.record(tile) }
            server.didRunAction = { action in recents.record(action) }
            await server.start()
        }
    }

    var body: some Scene {
        Window("Fiple", id: "main") {
            MainWindowView(store: store, server: server, recents: recents, pinned: pinned)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 780)

        // A lightweight menu-bar item keeps the pairing code and status one click
        // away even when the main window is closed.
        MenuBarExtra {
            MenuContentView(server: server)
                .task { await server.start() }
        } label: {
            // A rasterised *template* image, not the SwiftUI view directly:
            // macOS mangles a custom-shape MenuBarExtra label (it rendered as a
            // dark blob). As a template, the "F" is tinted by the system — crisp
            // white on a dark bar, black on a light one.
            Image(nsImage: Self.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    /// The "F" mark rendered once into a template NSImage for the menu bar.
    private static let menuBarIcon: NSImage = {
        let renderer = ImageRenderer(content: FipleMark(size: 16, style: Color.black).padding(1))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 14, height: 18))
        image.isTemplate = true // let the menu bar tint it for light/dark
        return image
    }()
}
