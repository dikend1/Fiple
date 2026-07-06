import Foundation
import Testing
@testable import FipleKit

@Suite("Scrollback buffer")
struct ScrollbackBufferTests {
    @Test("Below capacity, everything is retained in order")
    func retainsWhenSmall() {
        var buffer = ScrollbackBuffer(capacity: 100)
        buffer.append(Data("hello ".utf8))
        buffer.append(Data("world".utf8))
        #expect(buffer.snapshot() == Data("hello world".utf8))
    }

    @Test("Past capacity, the oldest bytes are evicted")
    func evictsOldest() {
        var buffer = ScrollbackBuffer(capacity: 5)
        buffer.append(Data("abc".utf8))
        buffer.append(Data("defg".utf8)) // total "abcdefg" -> keep last 5
        #expect(buffer.snapshot() == Data("cdefg".utf8))
        #expect(buffer.count == 5)
    }

    @Test("A single append larger than capacity keeps only its tail")
    func oversizedAppendKeepsTail() {
        var buffer = ScrollbackBuffer(capacity: 4)
        buffer.append(Data("0123456789".utf8))
        #expect(buffer.snapshot() == Data("6789".utf8))
    }

    @Test("An exactly-capacity buffer replays the whole window")
    func exactCapacity() {
        var buffer = ScrollbackBuffer(capacity: 3)
        buffer.append(Data("xyz".utf8))
        #expect(buffer.snapshot() == Data("xyz".utf8))
        #expect(buffer.count == 3)
    }

    @Test("A fresh buffer snapshots empty")
    func startsEmpty() {
        let buffer = ScrollbackBuffer(capacity: 10)
        #expect(buffer.snapshot().isEmpty)
        #expect(buffer.count == 0)
    }
}
