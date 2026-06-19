import Foundation
import Observation

/// A toggleable focus mode shown in the "Focus" panel.
///
/// NOTE: for now only the on/off state is persisted — the actual side effects
/// (silencing notifications, launching focus apps, Do Not Disturb) are not yet
/// wired up and are tracked as follow-up work.
struct FocusMode: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var name: String
    var subtitle: String
    var iconSystemName: String
    var colorHex: String
    var isOn: Bool

    init(
        id: UUID = UUID(),
        name: String,
        subtitle: String,
        iconSystemName: String,
        colorHex: String,
        isOn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
        self.colorHex = colorHex
        self.isOn = isOn
    }
}

/// Mac-local focus-mode state, persisted as JSON in Application Support.
@MainActor
@Observable
final class FocusStore {
    private(set) var modes: [FocusMode]

    @ObservationIgnored private let fileURL: URL

    init() {
        fileURL = AppSupport.fileURL(named: "focus.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([FocusMode].self, from: data), !saved.isEmpty {
            modes = saved
        } else {
            modes = FocusStore.seed
        }
    }

    func toggle(_ id: UUID) {
        guard let index = modes.firstIndex(where: { $0.id == id }) else { return }
        modes[index].isOn.toggle()
        commit()
    }

    func setOn(_ isOn: Bool, for id: UUID) {
        guard let index = modes.firstIndex(where: { $0.id == id }) else { return }
        modes[index].isOn = isOn
        commit()
    }

    private func commit() {
        if let data = try? JSONEncoder().encode(modes) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static let seed: [FocusMode] = [
        FocusMode(name: "Deep Work", subtitle: "Silence notifications, focus music, no distractions",
                  iconSystemName: "target", colorHex: "#3B82F6"),
        FocusMode(name: "Start Coding", subtitle: "Open dev setup, terminal, and focus apps",
                  iconSystemName: "chevron.left.forwardslash.chevron.right", colorHex: "#84CC16"),
        FocusMode(name: "Meeting Mode", subtitle: "Prepare for calls and meetings",
                  iconSystemName: "person.2.fill", colorHex: "#8B5CF6"),
        FocusMode(name: "Night Mode", subtitle: "Wind down and relax",
                  iconSystemName: "moon.fill", colorHex: "#6366F1"),
    ]
}
