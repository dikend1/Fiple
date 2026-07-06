import Foundation
import Testing
@testable import FipleKit

@Suite("Master password")
struct MasterPasswordTests {
    // Keep the test fast: a low iteration count exercises the same code path.
    private let iterations = 1_000

    @Test("The correct password verifies")
    func correctVerifies() {
        let record = MasterPassword.make("correct horse battery", iterations: iterations)
        #expect(MasterPassword.verify("correct horse battery", against: record))
    }

    @Test("A wrong password is rejected")
    func wrongRejected() {
        let record = MasterPassword.make("s3cret", iterations: iterations)
        #expect(!MasterPassword.verify("s3crets", against: record))
        #expect(!MasterPassword.verify("", against: record))
    }

    @Test("The same password yields distinct salts and hashes")
    func distinctSalts() {
        let a = MasterPassword.make("same", iterations: iterations)
        let b = MasterPassword.make("same", iterations: iterations)
        #expect(a.salt != b.salt)
        #expect(a.hash != b.hash)
        // ...yet both verify.
        #expect(MasterPassword.verify("same", against: a))
        #expect(MasterPassword.verify("same", against: b))
    }

    @Test("A record survives Codable round-trip and still verifies")
    func codableRoundTrip() throws {
        let record = MasterPassword.make("portable", iterations: iterations)
        let data = try JSONEncoder().encode(record)
        let restored = try JSONDecoder().decode(MasterPasswordRecord.self, from: data)
        #expect(restored == record)
        #expect(MasterPassword.verify("portable", against: restored))
    }
}
