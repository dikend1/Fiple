import FipleKit
import SwiftUI

@main
struct FipleMacApp: App {
    @State private var store: TileStore
    @State private var server: ServerController

    init() {
        let store = TileStore()
        _store = State(initialValue: store)
        _server = State(initialValue: ServerController(store: store))
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
