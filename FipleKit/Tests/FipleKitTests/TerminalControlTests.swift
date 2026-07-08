import Foundation
import Testing
@testable import FipleKit

@Suite("Terminal control messages")
struct TerminalControlTests {
    @Test("Client control messages round-trip through JSON")
    func clientRoundTrip() throws {
        let messages: [TerminalClientControl] = [
            .auth(token: "tok-123", passwordProof: "proof-abc", resumeSessionID: nil),
            .auth(token: "tok-123", passwordProof: "proof-abc", resumeSessionID: "sess-1"),
            .endSession(sessionID: "sess-2")
        ]
        for message in messages {
            let data = try MessageCodec.encode(message)
            let decoded = try MessageCodec.decode(TerminalClientControl.self, from: data)
            #expect(decoded == message)
        }
    }

    @Test("Server control messages round-trip through JSON")
    func serverRoundTrip() throws {
        let messages: [TerminalServerControl] = [
            .authOK(sessionID: "sess-1"),
            .authFailed(reason: .lockedOut),
            .sessionEnded(exitCode: 0),
            .sessionEnded(exitCode: nil)
        ]
        for message in messages {
            let data = try MessageCodec.encode(message)
            let decoded = try MessageCodec.decode(TerminalServerControl.self, from: data)
            #expect(decoded == message)
        }
    }

    @Test("A resize payload round-trips")
    func resizeRoundTrip() throws {
        let resize = TerminalResize(cols: 120, rows: 40)
        let data = try MessageCodec.encode(resize)
        #expect(try MessageCodec.decode(TerminalResize.self, from: data) == resize)
    }

    @Test("An unknown auth-fail reason from a newer peer decodes to badPassword")
    func unknownReasonTolerated() throws {
        let json = Data(#"{"type":"authFailed","reason":"quantumTamper"}"#.utf8)
        let decoded = try MessageCodec.decode(TerminalServerControl.self, from: json)
        #expect(decoded == .authFailed(reason: .badPassword))
    }

    @Test("An unknown message type is skipped by decodeIfKnown, not fatal")
    func unknownTypeSkipped() throws {
        let json = Data(#"{"type":"teleport","token":"x"}"#.utf8)
        let decoded = try MessageCodec.decodeIfKnown(TerminalClientControl.self, from: json)
        #expect(decoded == nil)
    }
}
