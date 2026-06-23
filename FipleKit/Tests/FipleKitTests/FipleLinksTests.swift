import Foundation
import Testing
@testable import FipleKit

struct FipleLinksTests {
    @Test func allLinksUseHTTPSOnFipleDomain() {
        for url in [FipleLinks.privacy, FipleLinks.terms, FipleLinks.support] {
            #expect(url.scheme == "https")
            #expect(url.host == "fiple.app")
        }
    }

    @Test func linksPointAtTheirRespectiveHashRoutes() {
        // The site is a hash-routed SPA, so the page lives in the URL fragment.
        #expect(FipleLinks.privacy.fragment == "/privacy")
        #expect(FipleLinks.terms.fragment == "/terms")
        #expect(FipleLinks.support.fragment == "/support")
    }
}
