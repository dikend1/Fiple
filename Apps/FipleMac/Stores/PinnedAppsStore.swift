import AppKit
import FipleKit
import Observation

/// The user's "Fiple Bar": an ordered list of quick actions (apps, websites or
/// files) shown in the Workspaces grid. Persisted locally; seeded once from the
/// actions already used by the workspaces so the bar isn't empty on first run.
@MainActor
@Observable
final class PinnedAppsStore {
    private(set) var actions: [Action]
    /// Notifies when the bar changes, so the server can re-sync it to the phone.
    @ObservationIgnored var didChange: (() -> Void)?
    private let key = "fiple.fipleBar"
    private let seededKey = "fiple.fipleBar.seeded"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Action].self, from: data) {
            actions = decoded
        } else {
            actions = []
        }
    }

    /// One-time seed from the distinct actions used by existing workspaces.
    func seedIfNeeded(from tiles: [Tile]) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        UserDefaults.standard.set(true, forKey: seededKey)
        guard actions.isEmpty else { return }

        var seen = Set<String>()
        var out: [Action] = []
        for tile in tiles {
            for action in tile.actions where seen.insert(Self.key(action.kind)).inserted {
                out.append(Action(kind: action.kind))
            }
        }
        actions = out
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

    /// Stable identity for de-duplication (one Fiple Bar entry per app/site/file).
    static func key(_ kind: ActionKind) -> String {
        switch kind {
        case let .launchApp(bundleID): "app:\(bundleID)"
        case let .openURL(url): "url:\(url.host() ?? url.absoluteString)"
        case let .openFile(path, _): "file:\(path)"
        }
    }
}
