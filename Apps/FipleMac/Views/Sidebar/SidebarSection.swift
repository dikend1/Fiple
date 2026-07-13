import Foundation

/// The navigable sections of the main window, grouped as in the design.
enum SidebarSection: String, CaseIterable, Identifiable {
    case workspaces, apps, websites
    case recent
    case terminal, smartTrash
    case devices, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspaces: "Workspaces"
        case .apps: "Apps"
        case .websites: "Websites"
        case .recent: "Recent"
        case .terminal: "Terminal"
        case .smartTrash: "Smart Trash"
        case .devices: "Devices"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .workspaces: "square.grid.2x2"
        case .apps: "shippingbox"
        case .websites: "globe"
        case .recent: "clock"
        case .terminal: "terminal"
        case .smartTrash: "trash"
        case .devices: "iphone.gen3"
        case .settings: "gearshape"
        }
    }

    /// Visual grouping with separators between groups. Terminal and Smart Trash
    /// are product features, not app preferences — they live as first-class
    /// pages (mirroring the iOS Tools tab), leaving Settings to app meta.
    static let groups: [[SidebarSection]] = [
        [.workspaces, .apps, .websites],
        [.recent],
        [.terminal, .smartTrash],
        [.devices, .settings],
    ]

    /// Whether this section is reachable in the current build. Terminal exists
    /// only in the non-sandboxed Developer ID build (see
    /// `TerminalController.isFeatureAvailable`); the sandboxed App Store build
    /// drops its sidebar entry.
    var isAvailable: Bool {
        switch self {
        case .terminal: return TerminalController.isFeatureAvailable
        default: return true
        }
    }

    /// `groups` with build-unavailable sections removed (empty groups dropped).
    /// The Tools group keeps Smart Trash, so no group disappears and the group
    /// labels stay index-aligned.
    static var visibleGroups: [[SidebarSection]] {
        groups.map { $0.filter(\.isAvailable) }.filter { !$0.isEmpty }
    }
}
