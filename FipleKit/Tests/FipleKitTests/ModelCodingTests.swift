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
            .runShortcut(name: "Start Coding"),
            .runShortcut(name: "Morning Routine"),
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
            subtitle: "Everything you need to code",
            iconSystemName: "chevron.left.forwardslash.chevron.right",
            colorHex: "#3B82F6",
            order: 2,
            actions: [
                Action(kind: .launchApp(bundleID: "com.todesktop.230313mzl4w4u92")),
                Action(kind: .openURL(URL(string: "https://github.com")!)),
                Action(kind: .runShortcut(name: "Open Project")),
            ]
        )
        #expect(tile.isWorkspace)
        #expect(tile.appCount == 1)
        #expect(tile.websiteCount == 1)
        #expect(tile.shortcutCount == 1)
        #expect(try roundTrip(tile) == tile)
    }

    @Test("Tile JSON without subtitle decodes with a nil subtitle")
    func tileSubtitleBackwardCompatibleDecoding() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Deep Work","iconSystemName":"brain","colorHex":"#8B5CF6","order":0,"actions":[]}
        """
        let tile = try MessageCodec.decode(Tile.self, from: Data(legacy.utf8))
        #expect(tile.subtitle == nil)
        #expect(tile.name == "Deep Work")
    }

    @Test("Tile carrying an embedded logo round-trips")
    func tileWithIconImageRoundTrip() throws {
        let tile = Tile(
            name: "Safari",
            iconSystemName: "safari",
            iconImageData: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
            colorHex: "#3B82F6",
            actions: [Action(kind: .launchApp(bundleID: "com.apple.Safari"))]
        )
        #expect(try roundTrip(tile) == tile)
    }

    @Test("Tile JSON without iconImageData decodes with a nil logo")
    func tileBackwardCompatibleDecoding() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Deep Work","iconSystemName":"brain","colorHex":"#8B5CF6","order":0,"actions":[]}
        """
        let tile = try MessageCodec.decode(Tile.self, from: Data(legacy.utf8))
        #expect(tile.iconImageData == nil)
        #expect(tile.name == "Deep Work")
    }

    @Test("ClientMessage round-trips")
    func clientMessageRoundTrip() throws {
        let id = UUID()
        #expect(try roundTrip(ClientMessage.pair(code: "0427")) == .pair(code: "0427"))
        #expect(try roundTrip(ClientMessage.run(tileID: id)) == .run(tileID: id))
        #expect(try roundTrip(ClientMessage.runAction(actionID: id)) == .runAction(actionID: id))
    }

    @Test("ServerMessage round-trips")
    func serverMessageRoundTrip() throws {
        let id = UUID()
        let messages: [ServerMessage] = [
            .paired(macID: "mac-1", macName: "Maksat's MacBook", token: "tok-abc"),
            .pairRejected(reason: .incorrectCode),
            .pairRejected(reason: .tooManyAttempts),
            .tilesSnapshot(tiles: [Tile(name: "Deep Work")]),
            .runResult(RunResult(tileID: id, actions: [.success(UUID()), .failure(UUID(), "not installed")])),
        ]
        for message in messages {
            #expect(try roundTrip(message) == message)
        }
    }
}
