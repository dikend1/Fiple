import Foundation

/// A single executable step performed on the Mac.
///
/// Each kind carries exactly the payload it needs, so an `Action` can never be
/// in an inconsistent state (e.g. a `launchApp` with a URL but no bundle id).
public enum ActionKind: Sendable, Equatable, Hashable {
    /// Launch an installed application by its bundle identifier.
    case launchApp(bundleID: String)
    /// Open a URL in the system default handler.
    case openURL(URL)
    /// Run an Apple Shortcut by name (triggered via the `shortcuts://` URL
    /// scheme on the Mac — sandbox-safe, no file-system access required).
    case runShortcut(name: String)
}

extension ActionKind: Codable {
    private enum Tag: String, Codable { case launchApp, openURL, runShortcut }
    private enum CodingKeys: String, CodingKey {
        case type, bundleID, url, name
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Tag.self, forKey: .type) {
        case .launchApp:
            self = .launchApp(bundleID: try c.decode(String.self, forKey: .bundleID))
        case .openURL:
            self = .openURL(try c.decode(URL.self, forKey: .url))
        case .runShortcut:
            self = .runShortcut(name: try c.decode(String.self, forKey: .name))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .launchApp(bundleID):
            try c.encode(Tag.launchApp, forKey: .type)
            try c.encode(bundleID, forKey: .bundleID)
        case let .openURL(url):
            try c.encode(Tag.openURL, forKey: .type)
            try c.encode(url, forKey: .url)
        case let .runShortcut(name):
            try c.encode(Tag.runShortcut, forKey: .type)
            try c.encode(name, forKey: .name)
        }
    }
}

/// An identified action belonging to a ``Tile``.
public struct Action: Identifiable, Sendable, Equatable, Hashable, Codable {
    public let id: UUID
    public var kind: ActionKind
    /// Real icon (the app's Finder icon) as a PNG, resolved on the Mac and
    /// attached only when a tile snapshot is sent to the
    /// remote — the phone can't resolve macOS icons itself. Omitted from JSON
    /// when nil, so stored tiles and older clients are unaffected. Website
    /// actions leave this nil; the remote fetches their favicon directly.
    public var iconImageData: Data?
    /// The app's real display name (e.g. "Books", "Cursor"), resolved on the Mac
    /// where `NSWorkspace` is available and attached to the tile snapshot. The
    /// phone can't resolve this from a bundle id alone — deriving it there yields
    /// junk like "I Books X" or "230313mzl4w4u92" — so it uses this when present.
    /// Omitted from JSON when nil, so stored tiles and older clients are
    /// unaffected. Website and shortcut actions leave it nil.
    public var displayName: String?

    public init(id: UUID = UUID(), kind: ActionKind, iconImageData: Data? = nil, displayName: String? = nil) {
        self.id = id
        self.kind = kind
        self.iconImageData = iconImageData
        self.displayName = displayName
    }

    /// Short, human-readable summary used in lists and feedback.
    public var displayLabel: String {
        switch kind {
        case let .launchApp(bundleID): "Launch \(bundleID)"
        case let .openURL(url): "Open \(url.absoluteString)"
        case let .runShortcut(name): "Run shortcut \(name)"
        }
    }
}
