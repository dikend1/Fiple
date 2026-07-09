import Foundation
import Testing
@testable import FipleKit

@Suite("Beam wire messages")
struct BeamWireTests {
    @Test("Beam client messages round-trip through JSON")
    func clientRoundTrip() throws {
        let id = UUID()
        let messages: [ClientMessage] = [
            .beamBegin(transferID: id, name: "IMG_1234.heic", totalBytes: 2_400_000),
            .beamChunk(transferID: id, bytes: Data([1, 2, 3, 4])),
            .beamEnd(transferID: id),
            .setClipboard(text: "https://example.com/from-qr"),
        ]
        for message in messages {
            let data = try MessageCodec.encode(message)
            #expect(try MessageCodec.decode(ClientMessage.self, from: data) == message)
        }
    }

    @Test("beamResult round-trips with and without a message")
    func serverRoundTrip() throws {
        let id = UUID()
        let messages: [ServerMessage] = [
            .beamResult(transferID: id, ok: true, message: nil),
            .beamResult(transferID: id, ok: false, message: "Disk full"),
        ]
        for message in messages {
            let data = try MessageCodec.encode(message)
            #expect(try MessageCodec.decode(ServerMessage.self, from: data) == message)
        }
    }
}

#if os(macOS)
@Suite("BeamReceiver")
struct BeamReceiverTests {
    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("beam-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Chunks assemble into the destination file")
    func assembly() throws {
        let folder = try makeFolder()
        let receiver = BeamReceiver(destination: folder)
        let id = UUID()
        let payload = Data((0 ..< 100_000).map { UInt8($0 % 251) })

        #expect(receiver.begin(id: id, name: "video.mov", totalBytes: Int64(payload.count)) == .accepted)
        for start in stride(from: 0, to: payload.count, by: 30_000) {
            let chunk = payload[start ..< min(start + 30_000, payload.count)]
            #expect(receiver.chunk(id: id, bytes: Data(chunk)) == .accepted)
        }
        #expect(receiver.end(id: id) == .completed(fileName: "video.mov"))
        #expect(try Data(contentsOf: folder.appendingPathComponent("video.mov")) == payload)
    }

    @Test("A colliding name gets a (2) suffix")
    func collision() throws {
        let folder = try makeFolder()
        try Data("existing".utf8).write(to: folder.appendingPathComponent("doc.pdf"))
        let receiver = BeamReceiver(destination: folder)
        let id = UUID()
        _ = receiver.begin(id: id, name: "doc.pdf", totalBytes: 3)
        _ = receiver.chunk(id: id, bytes: Data("new".utf8))
        #expect(receiver.end(id: id) == .completed(fileName: "doc (2).pdf"))
    }

    @Test("Path separators and leading dots are stripped from the name")
    func sanitizing() {
        #expect(BeamReceiver.sanitized("../../etc/passwd") == "passwd")
        #expect(BeamReceiver.sanitized(".hidden") == "hidden")
        #expect(BeamReceiver.sanitized("photo.jpg") == "photo.jpg")
        #expect(BeamReceiver.sanitized("...") == "Beamed file")
    }

    @Test("Chunks for an unknown transfer fail; short transfers are discarded")
    func guards() throws {
        let folder = try makeFolder()
        let receiver = BeamReceiver(destination: folder)
        #expect(receiver.chunk(id: UUID(), bytes: Data([1])) == .failed("Unknown transfer."))

        let id = UUID()
        _ = receiver.begin(id: id, name: "a.bin", totalBytes: 10)
        _ = receiver.chunk(id: id, bytes: Data([1, 2, 3]))
        if case .failed = receiver.end(id: id) {} else { Issue.record("short transfer must fail") }
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.bin").path))
    }

    @Test("Over-announced size is rejected at begin")
    func overCap() throws {
        let receiver = BeamReceiver(destination: try makeFolder())
        if case .failed = receiver.begin(id: UUID(), name: "huge.mov", totalBytes: BeamReceiver.maxBytes + 1) {}
        else { Issue.record("over-cap must fail") }
    }
}
#endif
