import Foundation
import Network
import Testing
@testable import FipleKit

@Suite("Transport loopback", .timeLimit(.minutes(1)))
struct TransportLoopbackTests {
    /// End-to-end over a real TCP socket on localhost: client sends a framed
    /// `ClientMessage`, server decodes it and replies with a `ServerMessage`.
    @Test("Framed messages round-trip over a real socket")
    func clientServerRoundTrip() async throws {
        let server = FipleServer()
        let port = try await server.start(deviceName: "TestMac", port: .any)
        #expect(port != 0)

        // Server side: accept first connection, echo a paired response.
        let serverReceived = Task { () -> ClientMessage in
            for await peer in await server.newConnections {
                for try await payload in await peer.messages {
                    let msg = try MessageCodec.decode(ClientMessage.self, from: payload)
                    try await peer.send(ServerMessage.paired(macID: "mac-1", macName: "TestMac", token: "tok-1"))
                    return msg
                }
            }
            throw TransportError.notConnected
        }

        // Client side: connect, send pair, await reply.
        let client = FipleClient()
        let peer = try await client.connect(host: "127.0.0.1", port: port)
        try await peer.send(ClientMessage.pair(code: "4271"))

        var reply: ServerMessage?
        for try await payload in await peer.messages {
            reply = try MessageCodec.decode(ServerMessage.self, from: payload)
            break
        }

        #expect(reply == .paired(macID: "mac-1", macName: "TestMac", token: "tok-1"))
        #expect(try await serverReceived.value == .pair(code: "4271"))

        await peer.close()
        await server.stop()
    }
}
