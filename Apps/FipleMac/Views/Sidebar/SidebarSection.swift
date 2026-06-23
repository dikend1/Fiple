import Foundation

/// The navigable sections of the main window, grouped as in the design.
enum SidebarSection: String, CaseIterable, Identifiable {
    case workspaces, apps, websites, shortcuts
    case recent
    case devices, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspaces: "Workspaces"
        case .apps: "Apps"
        case .websites: "Websites"
        case .shortcuts: "Shortcuts"
        case .recent: "Recent"
        case .devices: "Devices"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .workspaces: "square.grid.2x2"
        case .apps: "shippingbox"
        case .websites: "globe"
        case .shortcuts: "bolt"
        case .recent: "clock"
        case .devices: "iphone.gen3"
        case .settings: "gearshape"
        }
    }

    /// Visual grouping with separators between groups, matching the reference.
    static let groups: [[SidebarSection]] = [
        [.workspaces, .apps, .websites, .shortcuts],
        [.recent],
        [.devices, .settings],
    ]
}
