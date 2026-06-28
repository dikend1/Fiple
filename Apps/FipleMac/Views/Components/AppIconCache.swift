import AppKit

/// Session cache for resolved macOS app icons and display names, keyed by bundle
/// id. NSWorkspace / LaunchServices lookups are comparatively expensive and were
/// previously made directly inside SwiftUI `body` (so they re-ran on every
/// rerender, hover and scroll). Routing those reads through this cache turns the
/// repeat lookups into O(1) dictionary hits while leaving the first resolve and
/// the rendered result identical.
///
/// Main-actor isolated because NSWorkspace and the cache state are both
/// main-thread; every call site is already a SwiftUI view or `@MainActor` type.
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private var icons: [String: NSImage] = [:]
    private var names: [String: String] = [:]
    private var shortcuts: NSImage?

    private init() {}

    /// The app icon for a bundle id, resolved once via `SystemIcon` then cached.
    /// Returns nil when the bundle id can't be resolved (caller draws a fallback).
    func icon(bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        guard let image = SystemIcon.app(bundleID: bundleID) else { return nil }
        icons[bundleID] = image
        return image
    }

    /// The icon for an application whose file URL is already known (the Spotlight
    /// picker rows). Caches by bundle id and avoids a fresh
    /// `NSWorkspace.icon(forFile:)` per row redraw. Always returns an image, as
    /// NSWorkspace yields a generic icon for unknown files.
    func icon(bundleID: String, fileURL: URL) -> NSImage {
        if let cached = icons[bundleID] { return cached }
        let image = NSWorkspace.shared.icon(forFile: fileURL.path)
        icons[bundleID] = image
        return image
    }

    /// The app's Finder display name, resolved once then cached.
    func name(bundleID: String) -> String? {
        if let cached = names[bundleID] { return cached }
        guard let resolved = SystemIcon.appDisplayName(bundleID: bundleID) else { return nil }
        names[bundleID] = resolved
        return resolved
    }

    /// The Apple Shortcuts app icon, shared by every shortcut action and resolved
    /// at most once per session.
    func shortcutsIcon() -> NSImage? {
        if let shortcuts { return shortcuts }
        let image = SystemIcon.shortcutsAppIcon()
        shortcuts = image
        return image
    }
}
