import AppKit
import ApplicationServices
import FipleKit
import Foundation

/// Performs the four remote gestures on the Mac's frontmost application.
///
/// Copy/paste are synthesized keystrokes; enter/exit fullscreen set the focused
/// window's `AXFullScreen` attribute so the direction is deterministic (up always
/// enters, down always exits — never a blind toggle). All of this needs
/// Accessibility trust; without it macOS silently drops the events, so we report
/// `.notTrusted` and let the caller guide the user instead of failing quietly.
@MainActor
struct GestureExecutor {
    enum Outcome: Equatable {
        /// The gesture was carried out.
        case performed
        /// The app isn't trusted for Accessibility yet.
        case notTrusted
        /// Nothing to do — the receive-only `.unknown` sentinel from a newer phone.
        case ignored
    }

    // ANSI virtual key codes (Carbon `kVK_ANSI_C` / `kVK_ANSI_V`).
    private static let cKey: CGKeyCode = 0x08
    private static let vKey: CGKeyCode = 0x09

    func perform(_ action: GestureAction) -> Outcome {
        guard action != .unknown else { return .ignored }
        guard AXIsProcessTrusted() else { return .notTrusted }
        switch action {
        case .copy: postCommandKey(Self.cKey)
        case .paste: postCommandKey(Self.vKey)
        case .enterFullScreen: setFrontmostFullScreen(true)
        case .exitFullScreen: setFrontmostFullScreen(false)
        case .unknown: return .ignored
        }
        return .performed
    }

    /// Synthesize ⌘<key> to the session so it lands in the frontmost app.
    private func postCommandKey(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    /// Set (or clear) fullscreen on the frontmost app's focused window.
    private func setFrontmostFullScreen(_ value: Bool) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &focused
        ) == .success, let windowRef = focused else { return }
        // Safe: the focused-window attribute is always an AXUIElement.
        let window = windowRef as! AXUIElement
        let flag: CFBoolean = value ? kCFBooleanTrue : kCFBooleanFalse
        // `AXFullScreen` has no public constant but is the standard attribute the
        // window's green button toggles.
        AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, flag)
    }
}
