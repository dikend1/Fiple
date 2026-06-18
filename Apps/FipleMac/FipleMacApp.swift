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
        MenuBarExtra("Fiple", systemImage: "square.grid.2x2.fill") {
            MenuContentView(server: server)
                .task { await server.start() }
        }
        .menuBarExtraStyle(.window)

        Window("Fiple Tiles", id: "tiles") {
            TileManagerView(store: store, server: server)
                .frame(minWidth: 480, minHeight: 440)
        }
        .windowResizability(.contentSize)
    }
}
