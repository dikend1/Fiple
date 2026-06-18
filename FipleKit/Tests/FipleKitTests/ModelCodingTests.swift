import Foundation
import Testing
@testable import FipleKit

@Suite("Model & message coding")
struct ModelCodingTests {
    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try MessageCodec.encode(value)
        return try MessageCodec.decode(T.self, from: data)
    }

    @Test("ActionKind round-trips for every case")
    func actionKindRoundTrip() throws {
        let cases: [ActionKind] = [
            .launchApp(bundleID: "com.apple.dt.Xcode"),
            .openURL(URL(string: "https://github.com/dikend1/Fiple")!),
            .openFile(path: "/Users/me/proj", openWith: "com.todesktop.230313mzl4w4u92"),
            .openFile(path: "/Users/me/notes.md", openWith: nil),
        ]
        for kind in cases {
            let action = Action(kind: kind)
            #expect(try roundTrip(action) == action)
        }
    }

    @Test("Tile with workspace presets round-trips")
    func tileRoundTrip() throws {
        let tile = Tile(
            name: "Start Coding",
            iconSystemName: "chevron.left.forwardslash.chevron.right",
            colorHex: "#3B82F6",
            order: 2,
            actions: [
                Action(kind: .launchApp(bundleID: "com.todesktop.230313mzl4w4u92")),
                Action(kind: .openURL(URL(string: "https://github.com")!)),
            ]
        )
        #expect(tile.isWorkspace)
        #expect(try roundTrip(tile) == tile)
    }

    @Test("ClientMessage round-trips")
    func clientMessageRoundTrip() throws {
        let id = UUID()
        #expect(try roundTrip(ClientMessage.pair(code: "0427")) == .pair(code: "0427"))
        #expect(try roundTrip(ClientMessage.run(tileID: id)) == .run(tileID: id))
    }

    @Test("ServerMessage round-trips")
    func serverMessageRoundTrip() throws {
        let id = UUID()
        let messages: [ServerMessage] = [
            .paired(macID: "mac-1", macName: "Maksat's MacBook", token: "tok-abc"),
            .pairRejected(reason: "wrong code"),
            .tilesSnapshot(tiles: [Tile(name: "Deep Work")]),
            .runResult(RunResult(tileID: id, actions: [.success(UUID()), .failure(UUID(), "not installed")])),
        ]
        for message in messages {
            #expect(try roundTrip(message) == message)
        }
    }
}
