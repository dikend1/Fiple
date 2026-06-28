import Foundation

/// Pure, platform-agnostic helpers for the website-favicon service shared by the
/// Mac and iPhone apps. Both sides cache favicons in-memory keyed by host; this
/// type centralises the cache key and the request URL so the two clients dedupe
/// identically and can never drift apart.
///
/// Kept free of AppKit/UIKit so the key/URL logic is unit-testable in `FipleKit`
/// (the image objects themselves stay in the app targets).
public enum FaviconSource {
    /// Normalised cache key for a host: trimmed, lowercased, and with a leading
    /// `www.` removed so `www.Example.com` and `example.com` share one entry.
    /// Returns nil for an empty/whitespace host (nothing to fetch).
    public static func cacheKey(forHost host: String) -> String? {
        var key = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.hasPrefix("www.") { key.removeFirst("www.".count) }
        return key.isEmpty ? nil : key
    }

    /// The favicon request URL for a host, or nil when the host normalises to
    /// nothing. Uses the public Google s2 favicons service, sized in pixels.
    public static func url(forHost host: String, size: Int = 128) -> URL? {
        guard let key = cacheKey(forHost: host) else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(key)&sz=\(size)")
    }
}
