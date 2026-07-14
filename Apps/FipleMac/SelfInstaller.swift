import AppKit

/// Site-build install nicety: a zip-distributed app lands wherever the browser
/// put it (usually ~/Downloads) and macOS happily runs it from there. Proper
/// apps live in /Applications — so on launch outside it, the un-sandboxed
/// build offers to move itself there in one click (quitting and replacing an
/// older copy, e.g. the Mac App Store version), then relaunches from the new
/// home. The sandboxed MAS build is installed by the store and never triggers;
/// DEBUG runs from DerivedData are excluded so development is unaffected.
@MainActor
enum SelfInstaller {
    static func offerMoveToApplicationsIfNeeded() {
        #if !DEBUG
        guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil else { return }
        let bundleURL = Bundle.main.bundleURL
        guard !bundleURL.path.hasPrefix("/Applications/") else { return }
        let destination = URL(fileURLWithPath: "/Applications/Fiple.app")
        let replacing = FileManager.default.fileExists(atPath: destination.path)

        let alert = NSAlert()
        alert.messageText = "Move Fiple to Applications?"
        alert.informativeText = replacing
            ? "Fiple will move itself to your Applications folder, replacing the version that's already there, and reopen."
            : "Fiple will move itself to your Applications folder and reopen from there."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let fm = FileManager.default
            if replacing {
                // The old copy may still be running (a menu-bar app survives
                // its window closing) — ask every other instance to quit.
                let ownID = Bundle.main.bundleIdentifier ?? "com.maksatov.fipleapp"
                for app in NSRunningApplication.runningApplications(withBundleIdentifier: ownID)
                where app != NSRunningApplication.current {
                    app.terminate()
                }
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: bundleURL, to: destination)
            // Hand over to the installed copy and quit this stray one.
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: destination, configuration: config) { _, _ in }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NSApp.terminate(nil) }
        } catch {
            let fail = NSAlert()
            fail.messageText = "Couldn't move Fiple"
            fail.informativeText = "Please drag Fiple to the Applications folder manually. (\(error.localizedDescription))"
            fail.runModal()
        }
        #endif
    }
}
