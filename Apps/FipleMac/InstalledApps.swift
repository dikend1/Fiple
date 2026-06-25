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
    /// Enumerates installed applications via Spotlight (`NSMetadataQuery`).
    ///
    /// Reading `/Applications` directly is blocked by the App Sandbox, but a
    /// Spotlight query for application bundles is permitted — so this keeps the
    /// full, searchable picker working in a sandboxed (Mac App Store / Universal
    /// Purchase) build.
    @MainActor
    static func all() async -> [InstalledApp] {
        await SpotlightAppQuery().run()
    }

    /// The standard, user-facing application folders. Spotlight finds `.app`
    /// bundles everywhere (helpers buried in Library, apps embedded inside other
    /// apps, caches…); restricting to these roots gives the same clean list the
    /// user sees in `/Applications`, without scanning the directory ourselves.
    private static let appFolders: Set<String> = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    /// Pure transform from Spotlight results to sorted, de-duplicated apps,
    /// keeping only top-level apps in the standard application folders.
    @MainActor
    fileprivate static func build(from items: [NSMetadataItem]) -> [InstalledApp] {
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        for item in items {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  let bundleID = item.value(forAttribute: kMDItemCFBundleIdentifier as String) as? String
            else { continue }
            let url = URL(fileURLWithPath: path)
            // Only direct children of a standard app folder — drops embedded /
            // helper / Library-buried .app bundles.
            guard appFolders.contains(url.deletingLastPathComponent().path),
                  seen.insert(bundleID).inserted
            else { continue }
            let name = (item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String)?
                .replacingOccurrences(of: ".app", with: "")
                ?? url.deletingPathExtension().lastPathComponent
            apps.append(InstalledApp(bundleID: bundleID, name: name, url: url))
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Owns one `NSMetadataQuery` run and bridges its main-queue completion
/// notification to async/await without sending non-`Sendable` values across an
/// isolation boundary (everything stays on the main actor).
@MainActor
private final class SpotlightAppQuery {
    private let query = NSMetadataQuery()
    private var continuation: CheckedContinuation<[InstalledApp], Never>?
    private var observer: NSObjectProtocol?

    func run() async -> [InstalledApp] {
        query.predicate = NSPredicate(format: "kMDItemContentTypeTree == %@", "com.apple.application-bundle")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        return await withCheckedContinuation { cont in
            continuation = cont
            observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            }
            query.start()
        }
    }

    private func finish() {
        query.stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        let items = query.results.compactMap { $0 as? NSMetadataItem }
        continuation?.resume(returning: InstalledApps.build(from: items))
        continuation = nil
    }
}
