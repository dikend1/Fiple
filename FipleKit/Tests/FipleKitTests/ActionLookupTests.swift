import Foundation
import Testing
@testable import FipleKit

@Suite("ActionLookup — remote runAction resolves to saved actions only")
struct ActionLookupTests {
    private let safari = Action(kind: .launchApp(bundleID: "com.apple.Safari"))
    private let docs = Action(kind: .openURL(URL(string: "https://docs.example.com")!))
    private let shortcut = Action(kind: .runShortcut(name: "Morning Routine"))

    private func makeTile(_ actions: [Action]) -> Tile {
        Tile(name: "Work", actions: actions)
    }

    @Test("resolves an id present in the Fiple Bar to the saved action")
    func resolvesFromFipleBar() {
        let resolved = ActionLookup.resolve(safari.id, fipleBar: [safari, docs], tiles: [])
        #expect(resolved == safari)
        // The payload is the saved one, not anything a client could supply.
        #expect(resolved?.kind == .launchApp(bundleID: "com.apple.Safari"))
    }

    @Test("resolves an id present in a tile's actions")
    func resolvesFromTiles() {
        let tile = makeTile([shortcut])
        #expect(ActionLookup.resolve(shortcut.id, fipleBar: [], tiles: [tile]) == shortcut)
    }

    @Test("rejects an unknown id (the attacker case)")
    func rejectsUnknownID() {
        // A paired client tries to trigger an action the Mac never saved.
        #expect(ActionLookup.resolve(UUID(), fipleBar: [safari], tiles: [makeTile([docs])]) == nil)
    }

    @Test("a foreign app the client crafts is rejected: only its id matters, and it isn't saved")
    func rejectsForeignApp() {
        // Simulate a malicious client that knows a juicy bundle id and builds an
        // Action for it. Under the new model the client can only send an id; an
        // id for an action the Mac never saved resolves to nil → rejected.
        let attacker = Action(kind: .launchApp(bundleID: "com.apple.Terminal"))
        let resolved = ActionLookup.resolve(attacker.id, fipleBar: [safari], tiles: [])
        #expect(resolved == nil)
    }

    @Test("a foreign shortcut id is rejected")
    func rejectsForeignShortcut() {
        let attacker = Action(kind: .runShortcut(name: "Wipe Disk"))
        #expect(ActionLookup.resolve(attacker.id, fipleBar: [shortcut], tiles: []) == nil)
    }

    @Test("Fiple Bar takes precedence over tiles for the same id")
    func fipleBarPrecedence() {
        // Same id, different saved payloads — the Fiple Bar copy wins.
        let barCopy = Action(id: safari.id, kind: .launchApp(bundleID: "com.apple.Safari"))
        let tileCopy = Action(id: safari.id, kind: .launchApp(bundleID: "com.other.App"))
        let resolved = ActionLookup.resolve(safari.id, fipleBar: [barCopy], tiles: [makeTile([tileCopy])])
        #expect(resolved == barCopy)
    }
}
