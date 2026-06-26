import AppKit
import FipleKit
import Foundation

/// Lists the user's Apple Shortcuts via the scriptable "Shortcuts Events" target.
///
/// Sandbox notes (hard-won): the plain `com.apple.security.automation.apple-events`
/// entitlement is NOT enough — Apple events to "Shortcuts Events" fail with -600
/// ("Application isn't running") before TCC is even consulted, by name or bundle
/// id, helper running or not. What makes it work in the sandbox is the
/// `com.apple.security.temporary-exception.apple-events` entitlement listing
/// `com.apple.shortcuts.events` (see Fiple.entitlements). We still launch the
/// helper ourselves via LaunchServices first, since the sandbox blocks the
/// implicit auto-launch. Runs on an actor (off the main thread) and caches the
/// result so re-opening the editor is instant.
actor InstalledShortcuts {
    static let shared = InstalledShortcuts()
    private static let eventsBundleID = "com.apple.shortcuts.events"
    private var cached: [String]?

    func all() async -> [String] {
        if let cached, !cached.isEmpty { return cached }
        let names = await Self.fetch()
        if !names.isEmpty { cached = names }
        return names
    }

    @discardableResult
    func reload() async -> [String] {
        let names = await Self.fetch()
        if !names.isEmpty { cached = names }
        return names
    }

    private static func fetch() async -> [String] {
        await ensureEventsRunning()
        return runScript()
    }

    private static func ensureEventsRunning() async {
        if isEventsRunning() { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: eventsBundleID) else {
            FipleLog.execution.error("Shortcuts Events not found on this system")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        } catch {
            FipleLog.execution.error("failed to launch Shortcuts Events: \(error.localizedDescription)")
            return
        }
        for _ in 0..<20 {
            if isEventsRunning() { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private static func isEventsRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: eventsBundleID).isEmpty
    }

    private static func runScript() -> [String] {
        let source = #"tell application id "com.apple.shortcuts.events" to get name of every shortcut"#
        guard let script = NSAppleScript(source: source) else { return [] }

        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            let msg = error[NSAppleScript.errorMessage] as? String ?? "unknown"
            FipleLog.execution.error("shortcuts list failed — code \(code): \(msg)")
            return []
        }

        var names: [String] = []
        if descriptor.numberOfItems > 0 {
            for i in 1...descriptor.numberOfItems {
                if let name = descriptor.atIndex(i)?.stringValue, !name.isEmpty {
                    names.append(name)
                }
            }
        } else if let single = descriptor.stringValue, !single.isEmpty {
            names.append(single)
        }
        FipleLog.execution.info("shortcuts listed: \(names.count)")
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
