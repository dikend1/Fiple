import Foundation
import Testing
@testable import FipleKit

@Suite("ActionPolicy URL allowlist")
struct ActionPolicyTests {
    @Test("allows http and https")
    func allowsWebSchemes() {
        #expect(ActionPolicy.allowsOpening(URL(string: "http://example.com")!))
        #expect(ActionPolicy.allowsOpening(URL(string: "https://example.com/path?q=1")!))
        // Scheme comparison is case-insensitive.
        #expect(ActionPolicy.allowsOpening(URL(string: "HTTPS://Example.com")!))
    }

    @Test("blocks file and custom schemes")
    func blocksDangerousSchemes() {
        #expect(!ActionPolicy.allowsOpening(URL(string: "file:///Users/me/evil.command")!))
        #expect(!ActionPolicy.allowsOpening(URL(string: "ftp://host/x")!))
        #expect(!ActionPolicy.allowsOpening(URL(string: "shortcuts://run-shortcut?name=x")!))
        #expect(!ActionPolicy.allowsOpening(URL(string: "javascript:alert(1)")!))
        #expect(!ActionPolicy.allowsOpening(URL(string: "x-apple.systempreferences:y")!))
    }

    @Test("blocks schemeless / relative URLs")
    func blocksSchemeless() {
        #expect(!ActionPolicy.allowsOpening(URL(string: "/etc/passwd")!))
        #expect(!ActionPolicy.allowsOpening(URL(string: "example.com")!))
    }
}
