import Foundation
import Testing
@testable import FipleKit

@Suite("Gesture wire messages")
struct GestureWireTests {
    @Test("All four gesture actions round-trip through ClientMessage")
    func gestureRoundTrip() throws {
        let messages: [ClientMessage] = [
            .gesture(.copy),
            .gesture(.paste),
            .gesture(.enterFullScreen),
            .gesture(.exitFullScreen),
        ]
        for message in messages {
            let data = try MessageCodec.encode(message)
            #expect(try MessageCodec.decode(ClientMessage.self, from: data) == message)
        }
    }

    @Test("gesture is a known wire type")
    func gestureIsKnown() {
        #expect(ClientMessage.knownTypes.contains("gesture"))
    }

    @Test("An unknown future gesture decodes to a no-op rather than throwing")
    func unknownGestureIsNoOp() throws {
        // A newer phone may send a gesture this build doesn't know. It must not
        // tear the session down (malformed-known-type is fatal); it decodes to
        // the receive-only .unknown sentinel that the Mac ignores.
        let json = #"{"type":"gesture","action":"teleport"}"#
        let decoded = try MessageCodec.decodeIfKnown(ClientMessage.self, from: Data(json.utf8))
        #expect(decoded == .gesture(.unknown))
    }
}

@Suite("Swipe to gesture mapping")
struct SwipeGestureMappingTests {
    @Test("Two- and four-finger swipes map to the four actions")
    func mappedSwipes() {
        #expect(GestureAction.from(fingers: 2, direction: .up) == .copy)
        #expect(GestureAction.from(fingers: 2, direction: .down) == .paste)
        #expect(GestureAction.from(fingers: 4, direction: .up) == .enterFullScreen)
        #expect(GestureAction.from(fingers: 4, direction: .down) == .exitFullScreen)
    }

    @Test("Unmapped finger counts produce no action")
    func unmappedSwipes() {
        #expect(GestureAction.from(fingers: 1, direction: .up) == nil)
        #expect(GestureAction.from(fingers: 3, direction: .down) == nil)
        #expect(GestureAction.from(fingers: 5, direction: .up) == nil)
    }

    @Test("The unknown sentinel is never produced by a real swipe")
    func sentinelNeverMapped() {
        for fingers in 0...6 {
            for direction in [SwipeDirection.up, .down] {
                #expect(GestureAction.from(fingers: fingers, direction: direction) != .unknown)
            }
        }
    }
}
