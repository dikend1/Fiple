import Foundation
import Testing
@testable import FipleKit

struct FipleLinksTests {
    @Test func allLinksUseHTTPSOnFipleDomain() {
        for url in [FipleLinks.privacy, FipleLinks.terms, FipleLinks.support, FipleLinks.download] {
            #expect(url.scheme == "https")
            #expect(url.host == "fiple.app")
        }
    }

    @Test func linksPointAtTheirRespectivePaths() {
        // The site now uses real path routes (the #/ hash route was dropped so
        // the pages actually load), so the page lives in the URL path.
        #expect(FipleLinks.privacy.path == "/privacy")
        #expect(FipleLinks.terms.path == "/terms")
        #expect(FipleLinks.support.path == "/support")
        #expect(FipleLinks.download.path == "/download")
        for url in [FipleLinks.privacy, FipleLinks.terms, FipleLinks.support, FipleLinks.download] {
            #expect(url.fragment == nil)
        }
    }
}
