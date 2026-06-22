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
    /// Open a file or folder, optionally with a specific app (by bundle id).
    case openFile(path: String, openWith: String?)
}

extension ActionKind: Codable {
    private enum Tag: String, Codable { case launchApp, openURL, openFile }
    private enum CodingKeys: String, CodingKey {
        case type, bundleID, url, path, openWith
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Tag.self, forKey: .type) {
        case .launchApp:
            self = .launchApp(bundleID: try c.decode(String.self, forKey: .bundleID))
        case .openURL:
            self = .openURL(try c.decode(URL.self, forKey: .url))
        case .openFile:
            self = .openFile(
                path: try c.decode(String.self, forKey: .path),
                openWith: try c.decodeIfPresent(String.self, forKey: .openWith)
            )
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
        case let .openFile(path, openWith):
            try c.encode(Tag.openFile, forKey: .type)
            try c.encode(path, forKey: .path)
            try c.encodeIfPresent(openWith, forKey: .openWith)
        }
    }
}

/// An identified action belonging to a ``Tile``.
public struct Action: Identifiable, Sendable, Equatable, Hashable, Codable {
    public let id: UUID
    public var kind: ActionKind
    /// Real icon (the app's icon, or a file/folder's Finder icon) as a PNG,
    /// resolved on the Mac and attached only when a tile snapshot is sent to the
    /// remote — the phone can't resolve macOS icons itself. Omitted from JSON
    /// when nil, so stored tiles and older clients are unaffected. Website
    /// actions leave this nil; the remote fetches their favicon directly.
    public var iconImageData: Data?

    public init(id: UUID = UUID(), kind: ActionKind, iconImageData: Data? = nil) {
        self.id = id
        self.kind = kind
        self.iconImageData = iconImageData
    }

    /// Short, human-readable summary used in lists and feedback.
    public var displayLabel: String {
        switch kind {
        case let .launchApp(bundleID): "Launch \(bundleID)"
        case let .openURL(url): "Open \(url.absoluteString)"
        case let .openFile(path, _): "Open \(path)"
        }
    }
}
