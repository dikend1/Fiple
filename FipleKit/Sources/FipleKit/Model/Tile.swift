import Foundation

/// A user-defined unit on the Mac that runs one or more ``Action``s.
///
/// A tile with more than one action is a "workspace preset" — there is no
/// separate workspace type, by design (see TRD/BRD).
public struct Tile: Identifiable, Sendable, Equatable, Hashable, Codable {
    public let id: UUID
    public var name: String
    /// One-line tagline shown under the name on workspace cards
    /// (e.g. "Everything you need to code"). Optional and omitted from JSON when
    /// nil, so older tiles — and the iPhone snapshot — decode unchanged.
    public var subtitle: String?
    /// SF Symbol name shown on the tile when ``iconImageData`` is absent.
    public var iconSystemName: String
    /// Optional PNG of a real logo (e.g. an app icon or a site favicon). When
    /// present it is rendered instead of ``iconSystemName`` — including on the
    /// iPhone remote, which is why it travels inside the tile snapshot. The key
    /// is omitted from JSON when nil, so older tiles decode unchanged.
    public var iconImageData: Data?
    /// Hex string, e.g. `#3B82F6`.
    public var colorHex: String
    /// Position in the grid; lower comes first.
    public var order: Int
    public var actions: [Action]

    public init(
        id: UUID = UUID(),
        name: String,
        subtitle: String? = nil,
        iconSystemName: String = "square.grid.2x2",
        iconImageData: Data? = nil,
        colorHex: String = "#2DA44E",
        order: Int = 0,
        actions: [Action] = []
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
        self.iconImageData = iconImageData
        self.colorHex = colorHex
        self.order = order
        self.actions = actions
    }

    /// True when this tile restores a multi-step working context.
    public var isWorkspace: Bool { actions.count > 1 }

    /// Number of app-launch actions — the "Apps" stat on a workspace card.
    public var appCount: Int {
        actions.filter { if case .launchApp = $0.kind { true } else { false } }.count
    }

    /// Number of URL actions — the "Websites" stat on a workspace card.
    public var websiteCount: Int {
        actions.filter { if case .openURL = $0.kind { true } else { false } }.count
    }
}
