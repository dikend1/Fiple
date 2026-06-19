import AppKit
import FipleKit
import SwiftUI

@main
struct FipleMacApp: App {
    @State private var store: TileStore
    @State private var server: ServerController

    init() {
        let store = TileStore()
        let server = ServerController(store: store)
        _store = State(initialValue: store)
        _server = State(initialValue: server)
        // Advertise immediately at launch — the menu-bar popover is lazy, so we
        // cannot rely on its `.task` to start the server.
        Task { await server.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(server: server)
                .task { await server.start() }
        } label: {
            // The label is rendered eagerly at launch (unlike the lazy popover
            // content), so it's the reliable place to open the Tiles window
            // automatically — this app is a menu-bar accessory with no Dock icon.
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Window("Fiple Tiles", id: "tiles") {
            TileManagerView(store: store, server: server)
                .frame(minWidth: 480, minHeight: 440)
        }
        .windowResizability(.contentSize)
    }
}

/// The menu-bar icon. Opens the Tiles window once at launch and brings the app
/// to the front, so the user doesn't have to click through the popover first.
private struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "square.grid.2x2.fill")
            .task {
                openWindow(id: "tiles")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}
