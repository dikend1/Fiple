import Foundation
import Testing
@testable import FipleKit

@Suite("Wire forward compatibility")
struct WireCompatibilityTests {
    @Test("Unknown message type decodes to nil instead of throwing")
    func unknownTypeSkipped() throws {
        let futuristic = Data(#"{"type":"holoDeck","version":9,"payload":"x"}"#.utf8)
        #expect(try MessageCodec.decodeIfKnown(ClientMessage.self, from: futuristic) == nil)
        #expect(try MessageCodec.decodeIfKnown(ServerMessage.self, from: futuristic) == nil)
    }

    @Test("Known message types still decode through the tolerant path")
    func knownTypeDecodes() throws {
        let pair = try MessageCodec.encode(ClientMessage.pair(code: "4271"))
        #expect(try MessageCodec.decodeIfKnown(ClientMessage.self, from: pair) == .pair(code: "4271"))

        let paired = try MessageCodec.encode(
            ServerMessage.paired(macID: "mac-1", macName: "Test", token: "tok")
        )
        #expect(
            try MessageCodec.decodeIfKnown(ServerMessage.self, from: paired)
                == .paired(macID: "mac-1", macName: "Test", token: "tok")
        )
    }

    @Test("Malformed payload of a known type is still an error")
    func malformedKnownTypeThrows() {
        let broken = Data(#"{"type":"pair"}"#.utf8) // missing `code`
        #expect(throws: Error.self) {
            _ = try MessageCodec.decodeIfKnown(ClientMessage.self, from: broken)
        }
    }

    @Test("Handshake messages carry the protocol version")
    func handshakeCarriesVersion() throws {
        for message: any Encodable in [
            ClientMessage.pair(code: "0000"),
            ClientMessage.reconnect(token: "tok"),
            ServerMessage.paired(macID: "m", macName: "n", token: "t"),
        ] {
            let data = try MessageCodec.encode(message)
            let envelope = try MessageCodec.decode(WireEnvelope.self, from: data)
            #expect(envelope.version == FipleService.protocolVersion)
        }
    }

    @Test("Envelope with extra unknown keys still peeks")
    func envelopeIgnoresExtraKeys() throws {
        let data = Data(#"{"type":"run","tileID":"00000000-0000-0000-0000-000000000000","futureKey":true}"#.utf8)
        let envelope = try MessageCodec.decode(WireEnvelope.self, from: data)
        #expect(envelope.type == "run")
        #expect(envelope.version == nil)
    }
}
