import Foundation

/// A multi-touch gesture the phone recognizes and asks the Mac to perform on its
/// frontmost application. A deliberately closed set (ADR-0002): the Mac's remote
/// vocabulary grows only by these named, audited actions — never an arbitrary
/// keystroke channel.
public enum GestureAction: String, Codable, Sendable, CaseIterable, Equatable {
    /// Copy the current selection (⌘C on the Mac).
    case copy
    /// Paste the clipboard (⌘V on the Mac).
    case paste
    /// Put the frontmost window into fullscreen.
    case enterFullScreen
    /// Take the frontmost window out of fullscreen.
    case exitFullScreen
    /// Receive-only sentinel for a gesture a newer phone sent that this build
    /// doesn't understand. The phone never sends it; the Mac treats it as a
    /// no-op so an unknown gesture can't tear the session down.
    case unknown
}

/// The vertical direction of a recognized swipe.
public enum SwipeDirection: Sendable, Equatable {
    case up
    case down
}

public extension GestureAction {
    /// Pure mapping from a recognized swipe to the action it triggers, or `nil`
    /// for a finger-count/direction combination that isn't bound. Kept free of
    /// UIKit so it can be unit-tested without a gesture recognizer. Never returns
    /// `.unknown` — that sentinel exists only for tolerant decoding.
    static func from(fingers: Int, direction: SwipeDirection) -> GestureAction? {
        switch (fingers, direction) {
        case (2, .up): return .copy
        case (2, .down): return .paste
        case (4, .up): return .enterFullScreen
        case (4, .down): return .exitFullScreen
        default: return nil
        }
    }
}
