import AppKit
import Foundation

/// A discovered application the user can pick when building a `launchApp` action.
struct InstalledApp: Identifiable, Hashable, Sendable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let url: URL

    /// The app's Finder icon, for display in the picker.
    @MainActor var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    /// The icon flattened to PNG bytes so it can be embedded in a `Tile` and
    /// shipped to the iPhone remote.
    @MainActor var iconPNG: Data? { AppIconRenderer.png(from: icon) }
}

/// Renders an `NSImage` to PNG at a fixed size — small enough to travel inside a
/// tile snapshot, large enough to stay crisp on the phone.
enum AppIconRenderer {
    static let side: CGFloat = 128

    @MainActor
    static func png(from image: NSImage) -> Data? {
        let target = NSSize(width: side, height: side)
        let resized = NSImage(size: target)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: .zero, operation: .copy, fraction: 1)
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return nil }
        return data
    }
}

enum InstalledApps {
    private static let searchPaths = [
        "/Applications",
        "/System/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    /// Enumerates installed `.app` bundles and reads their bundle ids, sorted by name.
    static func all() -> [InstalledApp] {
        let fm = FileManager.default
        var seen = Set<String>()
        var apps: [InstalledApp] = []

        for path in searchPaths {
            guard let entries = try? fm.contentsOfDirectory(atPath: path) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let url = URL(fileURLWithPath: path).appendingPathComponent(entry)
                guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier,
                      seen.insert(bundleID).inserted else { continue }
                let name = fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                apps.append(InstalledApp(bundleID: bundleID, name: name, url: url))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
