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
