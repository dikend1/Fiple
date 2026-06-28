import FipleKit
import UIKit

/// Session cache over the public favicon service for the iPhone remote. Mirrors
/// the Mac's `FaviconCache`: results are kept in memory keyed by the shared
/// `FaviconSource` host key so a favicon is fetched at most once per host per
/// session, instead of a fresh network request on every `AsyncImage` body
/// evaluation (scroll, hover, state change).
@MainActor
final class FaviconImageCache {
    static let shared = FaviconImageCache()
    private var cache: [String: UIImage] = [:]

    private init() {}

    func icon(for host: String) async -> UIImage? {
        guard let key = FaviconSource.cacheKey(forHost: host) else { return nil }
        if let cached = cache[key] { return cached }
        guard let url = FaviconSource.url(forHost: host),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return nil }
        cache[key] = image
        return image
    }
}
