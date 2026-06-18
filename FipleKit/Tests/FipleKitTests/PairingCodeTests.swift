import Foundation
import Testing
@testable import FipleKit

/// Deterministic RNG so random-code tests are reproducible.
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

@Suite("Pairing code")
struct PairingCodeTests {
    @Test("Accepts exactly four digits")
    func validCodes() {
        #expect(PairingCode("0000")?.value == "0000")
        #expect(PairingCode("4271")?.value == "4271")
        #expect(PairingCode(" 4271 ")?.value == "4271")
    }

    @Test("Rejects malformed codes")
    func invalidCodes() {
        #expect(PairingCode("123") == nil)
        #expect(PairingCode("12345") == nil)
        #expect(PairingCode("12a4") == nil)
        #expect(PairingCode("") == nil)
    }

    @Test("Random codes are always four digits")
    func randomCodesWellFormed() {
        var rng = SeededRNG(state: 42)
        for _ in 0..<1000 {
            let code = PairingCode.random(using: &rng)
            #expect(code.value.count == 4)
            #expect(PairingCode(code.value) != nil)
        }
    }
}
