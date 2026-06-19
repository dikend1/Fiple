import AppKit
import FipleKit
import SwiftUI

@main
struct FipleMacApp: App {
    @State private var store: TileStore
    @State private var server: ServerController
    @State private var recents: RecentStore
    @State private var focus: FocusStore

    init() {
        let store = TileStore()
        let recents = RecentStore()
        let server = ServerController(store: store)
        _store = State(initialValue: store)
        _server = State(initialValue: server)
        _recents = State(initialValue: recents)
        _focus = State(initialValue: FocusStore())
        // Wire launch history and start advertising on the main actor. Done in a
        // Task because App.init is nonisolated while these touch @MainActor state.
        Task { @MainActor in
            server.didRun = { tile in recents.record(tile) }
            await server.start()
        }
    }

    var body: some Scene {
        Window("Fiple", id: "main") {
            MainWindowView(store: store, server: server, recents: recents, focus: focus)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 780)

        // A lightweight menu-bar item keeps the pairing code and status one click
        // away even when the main window is closed.
        MenuBarExtra {
            MenuContentView(server: server)
                .task { await server.start() }
        } label: {
            Image(systemName: "square.grid.2x2.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
