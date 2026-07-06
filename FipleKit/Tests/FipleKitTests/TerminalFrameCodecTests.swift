import Foundation
import Testing
@testable import FipleKit

@Suite("Terminal frame codec")
struct TerminalFrameCodecTests {
    @Test("A data frame round-trips")
    func dataRoundTrip() throws {
        let frame = TerminalFrame(type: .data, payload: Data("hello".utf8))
        var decoder = TerminalFrameDecoder()
        let out = try decoder.append(TerminalFrameCodec.frame(frame))
        #expect(out == [frame])
    }

    @Test("Mixed frame types in one chunk decode in order")
    func mixedFrames() throws {
        let data = TerminalFrame(type: .data, payload: Data("ls\n".utf8))
        let resize = TerminalFrame(type: .resize, payload: Data(#"{"cols":80,"rows":24}"#.utf8))
        let ping = TerminalFrame(type: .ping)

        var chunk = try TerminalFrameCodec.frame(data)
        chunk.append(try TerminalFrameCodec.frame(resize))
        chunk.append(try TerminalFrameCodec.frame(ping))

        var decoder = TerminalFrameDecoder()
        #expect(try decoder.append(chunk) == [data, resize, ping])
    }

    @Test("An empty-payload frame (ping) round-trips")
    func emptyPayload() throws {
        let frame = TerminalFrame(type: .ping)
        var decoder = TerminalFrameDecoder()
        #expect(try decoder.append(TerminalFrameCodec.frame(frame)) == [frame])
    }

    @Test("A frame split across chunks is reassembled")
    func splitFrame() throws {
        let frame = TerminalFrame(type: .data, payload: Data((0..<1000).map { UInt8($0 % 256) }))
        let framed = try TerminalFrameCodec.frame(frame)
        let mid = framed.count / 2

        var decoder = TerminalFrameDecoder()
        #expect(try decoder.append(framed.prefix(mid)).isEmpty)
        #expect(try decoder.append(framed.suffix(from: mid)) == [frame])
    }

    @Test("An unknown type byte is rejected once the full frame arrives")
    func unknownType() throws {
        // type 0x09 is not a TerminalFrameType; zero-length payload.
        let bytes = Data([0x09, 0x00, 0x00, 0x00, 0x00])
        var decoder = TerminalFrameDecoder()
        #expect(throws: TerminalFrameError.unknownType(0x09)) {
            _ = try decoder.append(bytes)
        }
    }

    @Test("An oversized length prefix is rejected")
    func oversizedFrame() {
        var bytes = Data([TerminalFrameType.data.rawValue, 0xFF, 0xFF, 0xFF, 0xFF])
        bytes.append(Data("x".utf8))
        var decoder = TerminalFrameDecoder()
        #expect(throws: FrameError.self) { _ = try decoder.append(bytes) }
    }

    @Test("The sender refuses a payload larger than the cap")
    func oversizedSendRejected() {
        let frame = TerminalFrame(type: .data, payload: Data(count: FrameCodec.maxFrameSize + 1))
        #expect(throws: FrameError.frameTooLarge(FrameCodec.maxFrameSize + 1)) {
            _ = try TerminalFrameCodec.frame(frame)
        }
    }
}
