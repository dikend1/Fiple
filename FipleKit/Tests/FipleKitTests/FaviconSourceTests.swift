import Foundation
import Testing
@testable import FipleKit

@Suite("FaviconSource cache key & URL")
struct FaviconSourceTests {
    @Test("normalises a host into a stable, lowercased cache key")
    func cacheKeyNormalises() {
        #expect(FaviconSource.cacheKey(forHost: "GitHub.com") == "github.com")
        #expect(FaviconSource.cacheKey(forHost: "  Example.com ") == "example.com")
        #expect(FaviconSource.cacheKey(forHost: "news.ycombinator.com") == "news.ycombinator.com")
    }

    @Test("strips a leading www. so variants share one cache entry")
    func cacheKeyDedupesWWW() {
        #expect(FaviconSource.cacheKey(forHost: "www.google.com") == "google.com")
        #expect(FaviconSource.cacheKey(forHost: "www.Google.com")
                == FaviconSource.cacheKey(forHost: "google.com"))
        // Only a *leading* www. is stripped, not an embedded one.
        #expect(FaviconSource.cacheKey(forHost: "wwwexample.com") == "wwwexample.com")
    }

    @Test("an empty or whitespace host has no key and no URL")
    func emptyHostHasNoKeyOrURL() {
        #expect(FaviconSource.cacheKey(forHost: "") == nil)
        #expect(FaviconSource.cacheKey(forHost: "   ") == nil)
        #expect(FaviconSource.url(forHost: "") == nil)
        #expect(FaviconSource.url(forHost: "  ") == nil)
    }

    @Test("builds the favicon request URL from the normalised host")
    func buildsRequestURL() {
        #expect(FaviconSource.url(forHost: "www.GitHub.com")?.absoluteString
                == "https://www.google.com/s2/favicons?domain=github.com&sz=128")
        #expect(FaviconSource.url(forHost: "example.com", size: 64)?.absoluteString
                == "https://www.google.com/s2/favicons?domain=example.com&sz=64")
    }
}
