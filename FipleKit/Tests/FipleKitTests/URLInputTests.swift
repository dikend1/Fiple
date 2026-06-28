import Foundation
import Testing
@testable import FipleKit

@Suite("URLInput web URL parsing")
struct URLInputTests {
    @Test("defaults a missing scheme to https")
    func defaultsScheme() {
        #expect(URLInput.webURL(from: "github.com")?.absoluteString == "https://github.com")
        #expect(URLInput.webURL(from: "www.example.com/path?q=1")?.absoluteString
                == "https://www.example.com/path?q=1")
        #expect(URLInput.webURL(from: "  github.com  ")?.absoluteString == "https://github.com")
    }

    @Test("keeps an explicit http or https scheme as typed")
    func keepsExplicitWebScheme() {
        #expect(URLInput.webURL(from: "https://github.com")?.absoluteString == "https://github.com")
        #expect(URLInput.webURL(from: "http://example.com/x")?.absoluteString == "http://example.com/x")
        #expect(URLInput.webURL(from: "HTTPS://Example.com")?.scheme?.lowercased() == "https")
    }

    @Test("rejects empty input and non-web schemes")
    func rejectsInvalid() {
        #expect(URLInput.webURL(from: "") == nil)
        #expect(URLInput.webURL(from: "   ") == nil)
        // file:// would be blocked at run time; reject it at save time too.
        #expect(URLInput.webURL(from: "file:///etc/passwd") == nil)
    }

    @Test("every parsed URL is allowed by the execution policy")
    func parsedURLsAreRunnable() {
        for input in ["github.com", "https://news.ycombinator.com", "http://x.test/y"] {
            let url = URLInput.webURL(from: input)
            #expect(url != nil)
            #expect(ActionPolicy.allowsOpening(url!))
        }
    }
}
