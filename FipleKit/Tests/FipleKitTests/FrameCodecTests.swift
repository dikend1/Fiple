import Foundation
import Testing
@testable import FipleKit

@Suite("Frame codec")
struct FrameCodecTests {
    @Test("Single framed payload decodes back")
    func singleFrame() throws {
        let payload = Data("hello".utf8)
        var decoder = FrameDecoder()
        let out = try decoder.append(FrameCodec.frame(payload))
        #expect(out == [payload])
    }

    @Test("Multiple frames in one chunk all decode in order")
    func multipleFrames() throws {
        let a = Data("one".utf8), b = Data("two".utf8), c = Data("three".utf8)
        var chunk = FrameCodec.frame(a)
        chunk.append(FrameCodec.frame(b))
        chunk.append(FrameCodec.frame(c))

        var decoder = FrameDecoder()
        #expect(try decoder.append(chunk) == [a, b, c])
    }

    @Test("Payload split across chunks is reassembled")
    func splitPayload() throws {
        let payload = Data((0..<1000).map { UInt8($0 % 256) })
        let framed = FrameCodec.frame(payload)
        let mid = framed.count / 2

        var decoder = FrameDecoder()
        #expect(try decoder.append(framed.prefix(mid)).isEmpty)
        #expect(try decoder.append(framed.suffix(from: mid)) == [payload])
    }

    @Test("Oversized length prefix is rejected")
    func oversizedFrame() throws {
        var bytes = Data([0xFF, 0xFF, 0xFF, 0xFF]) // ~4GB claimed length
        bytes.append(Data("x".utf8))
        var decoder = FrameDecoder()
        #expect(throws: FrameError.self) { _ = try decoder.append(bytes) }
    }
}
