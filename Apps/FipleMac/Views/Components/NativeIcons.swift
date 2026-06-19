import AppKit
import SwiftUI

/// Resolves real macOS icons for an app bundle id or a file path.
enum SystemIcon {
    /// The installed app's icon, or nil when the bundle id can't be resolved.
    static func app(bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// The Finder icon for a file or folder (generic placeholder if it's gone).
    static func file(path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path)
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
