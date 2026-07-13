import Foundation

/// Recognizes the demo content Fiple 1.0 seeded on first launch, so 1.1 can
/// strip it from old installs and land "like new". 1.1 itself never seeds.
///
/// Matching is deliberately exact: a demo tile the user renamed or re-built is
/// their work now and must survive; only untouched copies are recognized.
public enum LegacyDemoSeed {
    /// Tiles with every one of the four 1.0 demo templates removed — but only
    /// exact matches (name, subtitle, icon, and the same actions in order).
    public static func nonDemoTiles(_ tiles: [Tile]) -> [Tile] {
        tiles.filter { !isDemoTile($0) }
    }

    /// Fiple Bar actions with the 1.0 auto-seeded entries removed. The seed
    /// was derived from the demo tiles, so its identity set is fixed; anything
    /// the user pinned themselves has a different app/host and stays.
    public static func nonSeedActions(_ actions: [Action]) -> [Action] {
        actions.filter { !seedBarKeys.contains(barKey($0.kind)) }
    }

    // MARK: - Internals

    private static func isDemoTile(_ tile: Tile) -> Bool {
        templates.contains { template in
            template.name == tile.name
                && template.subtitle == tile.subtitle
                && template.icon == tile.iconSystemName
                && template.actions == tile.actions.map(\.kind)
        }
    }

    /// Identity used by the 1.0 bar seed's de-duplication: one entry per app
    /// bundle id or website host.
    private static func barKey(_ kind: ActionKind) -> String {
        switch kind {
        case let .launchApp(bundleID): "app:\(bundleID)"
        case let .openURL(url): "url:\(url.host() ?? url.absoluteString)"
        }
    }

    /// The exact content of 1.0's `TileStore.seed`.
    private static let templates: [(name: String, subtitle: String, icon: String, actions: [ActionKind])] = [
        ("Start Coding", "Everything you need to code", "chevron.left.forwardslash.chevron.right",
         [.launchApp(bundleID: "com.apple.dt.Xcode"),
          .openURL(URL(string: "https://github.com")!),
          .launchApp(bundleID: "com.apple.Terminal")]),
        ("Design Session", "Design and prototype", "pencil.and.outline",
         [.launchApp(bundleID: "com.apple.Preview"),
          .openURL(URL(string: "https://figma.com")!),
          .openURL(URL(string: "https://dribbble.com")!)]),
        ("Deep Work", "Focus and get things done", "target",
         [.launchApp(bundleID: "com.apple.Notes"),
          .openURL(URL(string: "https://music.apple.com")!)]),
        ("Ship Mode", "Build, ship, repeat", "paperplane.fill",
         [.launchApp(bundleID: "com.apple.dt.Xcode"),
          .launchApp(bundleID: "com.apple.Terminal"),
          .openURL(URL(string: "https://github.com")!)]),
    ]

    /// Every bar identity the 1.0 seed could have produced (union of all
    /// template actions after de-duplication).
    private static let seedBarKeys: Set<String> =
        Set(templates.flatMap(\.actions).map(barKey))
}
