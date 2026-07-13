import AppKit
import FipleKit
import Observation

/// The user's "Fiple Bar": an ordered list of quick actions (apps, websites or
/// files) shown in the Workspaces grid. Persisted locally; starts empty on a
/// fresh install — the user pins what *they* use (auto-seeding from demo tiles
/// read as someone else's setup to new users).
@MainActor
@Observable
final class PinnedAppsStore {
    private(set) var actions: [Action]
    /// Notifies when the bar changes, so the server can re-sync it to the phone.
    @ObservationIgnored var didChange: (() -> Void)?
    private let key = "fiple.fipleBar"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Action].self, from: data) {
            actions = decoded
        } else {
            actions = []
        }
        dropLegacySeed()
    }

    /// 1.0 auto-filled the bar from the demo workspaces on first launch (and
    /// left the `…seeded` flag behind); 1.1 starts empty. If that flag is
    /// present, this one-time migration strips exactly the auto-seeded entries
    /// (recognition lives in `LegacyDemoSeed`, unit-tested in FipleKit) so an
    /// updated install lands "like new" — anything the user pinned themselves
    /// has a different identity and stays.
    private func dropLegacySeed() {
        let seededFlag = "fiple.fipleBar.seeded"
        guard UserDefaults.standard.bool(forKey: seededFlag) else { return }
        UserDefaults.standard.removeObject(forKey: seededFlag)
        let remaining = LegacyDemoSeed.nonSeedActions(actions)
        guard remaining.count != actions.count else { return }
        actions = remaining
        persist()
    }

    func add(_ kind: ActionKind) {
        let k = Self.key(kind)
        guard !actions.contains(where: { Self.key($0.kind) == k }) else { return }
        actions.append(Action(kind: kind))
        persist()
    }

    func remove(_ id: Action.ID) {
        actions.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(actions) {
            UserDefaults.standard.set(data, forKey: key)
        }
        didChange?()
    }

    /// Stable identity for de-duplication (one Fiple Bar entry per app/site/shortcut).
    static func key(_ kind: ActionKind) -> String {
        switch kind {
        case let .launchApp(bundleID): "app:\(bundleID)"
        case let .openURL(url): "url:\(url.host() ?? url.absoluteString)"
        }
    }
}
