import AppKit
import FipleKit
import SwiftUI

/// Resolves real macOS icons for an app bundle id.
enum SystemIcon {
    /// The installed app's icon, or nil when the bundle id can't be resolved.
    static func app(bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// The installed app's Finder display name (e.g. "Books"), or nil when the
    /// bundle id can't be resolved. Resolved here on the Mac and carried in the
    /// snapshot so the phone shows a real name, not a mangled bundle id.
    static func appDisplayName(bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// A small PNG of an action's real icon for transmission to the remote:
    /// the app icon. Websites and shortcuts return nil (the phone draws a
    /// favicon / SF Symbol itself).
    static func pngData(for kind: ActionKind, maxPixel: CGFloat = 128) -> Data? {
        switch kind {
        case let .launchApp(bundleID):
            return app(bundleID: bundleID)?.pngData(maxPixel: maxPixel)
        case .runShortcut, .openURL:
            return nil
        }
    }
}

private extension NSImage {
    /// Renders the image into a square PNG no larger than `maxPixel`, suitable
    /// for sending over the wire.
    func pngData(maxPixel: CGFloat) -> Data? {
        let side = min(maxPixel, max(size.width, size.height, 1))
        let target = NSSize(width: side, height: side)
        let resized = NSImage(size: target)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: target),
             from: NSRect(origin: .zero, size: size),
             operation: .copy, fraction: 1)
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// Shows an `NSImage` (a real app/file icon) on a neutral rounded tile, falling
/// back to an SF Symbol when the image is unavailable.
struct NativeIconTile: View {
    let image: NSImage?
    var fallbackSymbol: String = "app.dashed"
    var size: CGFloat = 32
    var cornerRadius: CGFloat = 9

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.12)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// Loads and shows a website's favicon, with a globe fallback while loading or
/// when offline. Results are cached per host for the session.
struct FaviconView: View {
    let host: String
    var size: CGFloat = 32
    var cornerRadius: CGFloat = 9

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(size * 0.16)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: host) { image = await FaviconCache.shared.icon(for: host) }
    }
}

/// Tiny session cache over the public favicon service.
@MainActor
final class FaviconCache {
    static let shared = FaviconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for host: String) async -> NSImage? {
        let key = host.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }
        guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(key)&sz=128"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data) else { return nil }
        cache[key] = image
        return image
    }
}
