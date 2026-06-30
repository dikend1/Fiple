import Foundation
import Testing
@testable import FipleKit

@Suite("Free-tier gate")
struct FreeTierGateTests {
    /// `n` identifiable items (tiles), ordered 0..<n.
    private func tiles(_ n: Int) -> [Tile] {
        (0..<n).map { Tile(name: "T\($0)", order: $0) }
    }

    @Test("Pro locks nothing, however many items")
    func proUnlocksAll() {
        #expect(FreeTierGate.lockedIDs(tiles(20), isPro: true).isEmpty)
    }

    @Test("At or under the free limit locks nothing")
    func underLimit() {
        #expect(FreeTierGate.lockedIDs(tiles(8), isPro: false).isEmpty)
        #expect(FreeTierGate.lockedIDs(tiles(3), isPro: false).isEmpty)
    }

    @Test("Beyond the free limit locks exactly the overflow, first 8 stay free")
    func overflowLocked() {
        let items = tiles(11)
        let locked = FreeTierGate.lockedIDs(items, isPro: false)
        #expect(locked == Set(items.suffix(3).map(\.id)))
        #expect(items.prefix(8).allSatisfy { !locked.contains($0.id) })
    }

    @Test("Custom free limit honored")
    func customLimit() {
        let items = tiles(5)
        #expect(FreeTierGate.lockedIDs(items, freeLimit: 2, isPro: false) == Set(items.suffix(3).map(\.id)))
    }

    @Test("Empty list and zero/negative limit are well-behaved")
    func edges() {
        #expect(FreeTierGate.lockedIDs([Tile](), isPro: false).isEmpty)
        let items = tiles(3)
        #expect(FreeTierGate.lockedIDs(items, freeLimit: 0, isPro: false) == Set(items.map(\.id)))
        #expect(FreeTierGate.lockedIDs(items, freeLimit: -5, isPro: false) == Set(items.map(\.id)))
    }
}
