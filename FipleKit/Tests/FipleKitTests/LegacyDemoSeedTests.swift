import Foundation
import Testing
@testable import FipleKit

struct LegacyDemoSeedTests {
    /// An exact untouched copy of a 1.0 demo template.
    private var untouchedDemo: Tile {
        Tile(
            name: "Start Coding",
            subtitle: "Everything you need to code",
            iconSystemName: "chevron.left.forwardslash.chevron.right",
            colorHex: "#84CC16",
            order: 0,
            actions: [
                Action(kind: .launchApp(bundleID: "com.apple.dt.Xcode")),
                Action(kind: .openURL(URL(string: "https://github.com")!)),
                Action(kind: .launchApp(bundleID: "com.apple.Terminal")),
            ]
        )
    }

    private var userTile: Tile {
        Tile(name: "Акции", subtitle: "мое", iconSystemName: "briefcase.fill",
             colorHex: "#2DA44E", order: 1,
             actions: [Action(kind: .launchApp(bundleID: "com.apple.Safari"))])
    }

    @Test func untouchedDemoTileIsRemoved() {
        let result = LegacyDemoSeed.nonDemoTiles([untouchedDemo, userTile])
        #expect(result.map(\.name) == ["Акции"])
    }

    @Test func renamedDemoTileSurvives() {
        var renamed = untouchedDemo
        renamed.name = "Мой кодинг"
        let result = LegacyDemoSeed.nonDemoTiles([renamed])
        #expect(result.count == 1)
    }

    @Test func demoTileWithEditedActionsSurvives() {
        var edited = untouchedDemo
        edited.actions.append(Action(kind: .launchApp(bundleID: "com.apple.Safari")))
        let result = LegacyDemoSeed.nonDemoTiles([edited])
        #expect(result.count == 1)
    }

    @Test func demoColorEditDoesNotProtect() {
        // Color isn't part of identity — the four templates are recognized by
        // name/subtitle/icon/actions, so a color-only tweak still counts as
        // untouched demo content.
        var recolored = untouchedDemo
        recolored.colorHex = "#000000"
        #expect(LegacyDemoSeed.nonDemoTiles([recolored]).isEmpty)
    }

    @Test func seededBarEntriesAreStrippedUserOnesKept() {
        let bar = [
            Action(kind: .launchApp(bundleID: "com.apple.dt.Xcode")),
            Action(kind: .openURL(URL(string: "https://github.com")!)),
            Action(kind: .launchApp(bundleID: "com.apple.Terminal")),
            Action(kind: .launchApp(bundleID: "com.apple.Preview")),
            Action(kind: .openURL(URL(string: "https://figma.com")!)),
            Action(kind: .openURL(URL(string: "https://dribbble.com")!)),
            Action(kind: .launchApp(bundleID: "com.apple.Notes")),
            Action(kind: .openURL(URL(string: "https://music.apple.com")!)),
            Action(kind: .launchApp(bundleID: "com.apple.Safari")),          // user's
            Action(kind: .openURL(URL(string: "https://fiple.app")!)),       // user's
        ]
        let result = LegacyDemoSeed.nonSeedActions(bar)
        #expect(result.count == 2)
        #expect(result.map(\.displayLabel) == ["Launch com.apple.Safari", "Open https://fiple.app"])
    }

    @Test func seedHostMatchesRegardlessOfURLShape() {
        // The 1.0 bar seed de-duplicated by host, so any URL form of a seed
        // host is the seeded entry (www./trailing slash variations aside, the
        // seed always stored the canonical https://host form).
        let bar = [Action(kind: .openURL(URL(string: "https://github.com")!))]
        #expect(LegacyDemoSeed.nonSeedActions(bar).isEmpty)
    }
}
