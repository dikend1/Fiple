import Foundation

/// Lists the user's Apple Shortcuts via the scriptable "Shortcuts Events"
/// target, using `NSAppleScript` (in-process Apple Events — no subprocess, so it
/// is sandbox-safe with the `com.apple.security.automation.apple-events`
/// entitlement and works in a Mac App Store / Universal Purchase build).
///
/// macOS prompts the user to allow automation of Shortcuts on first use. If the
/// user declines (or anything fails), this returns an empty list and the editor
/// falls back to letting the user type a shortcut name by hand.
@MainActor
enum InstalledShortcuts {
    static func all() async -> [String] {
        let source = #"tell application "Shortcuts Events" to get name of every shortcut"#
        guard let script = NSAppleScript(source: source) else { return [] }

        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        guard error == nil else { return [] }

        var names: [String] = []
        if descriptor.numberOfItems > 0 {
            for i in 1...descriptor.numberOfItems {           // AppleScript lists are 1-indexed
                if let name = descriptor.atIndex(i)?.stringValue, !name.isEmpty {
                    names.append(name)
                }
            }
        } else if let single = descriptor.stringValue, !single.isEmpty {
            names.append(single)
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
