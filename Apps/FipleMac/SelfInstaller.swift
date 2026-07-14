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

        if replacing {
            // The old copy may still be running (a menu-bar app survives its
            // window closing) — ask every other instance to quit.
            let ownID = Bundle.main.bundleIdentifier ?? "com.maksatov.fipleapp"
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: ownID)
            where app != NSRunningApplication.current {
                app.terminate()
            }
        }

        do {
            try replaceInUserland(from: bundleURL, to: destination, replacing: replacing)
        } catch {
            // A Mac App Store copy is installed by root — a user process can't
            // delete it. Do what Finder does: ask for admin rights once and
            // replace with elevated privileges. A cancelled prompt just leaves
            // things as they were.
            do {
                try replaceWithAdminPrivileges(from: bundleURL, to: destination)
            } catch SelfInstallError.cancelled {
                return
            } catch {
                let fail = NSAlert()
                fail.messageText = "Couldn't move Fiple"
                fail.informativeText = "Please drag Fiple to the Applications folder manually. (\(error.localizedDescription))"
                fail.runModal()
                return
            }
        }

        // Hand over to the installed copy and quit this stray one.
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: config) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NSApp.terminate(nil) }
        #endif
    }

    #if !DEBUG
    private enum SelfInstallError: Error { case cancelled, scriptFailed(String) }

    /// Plain FileManager replace — enough when the old copy (if any) belongs
    /// to the user.
    private static func replaceInUserland(from source: URL, to destination: URL, replacing: Bool) throws {
        let fm = FileManager.default
        if replacing { try fm.removeItem(at: destination) }
        try fm.copyItem(at: source, to: destination)
    }

    /// Finder-style privileged replace: one system password prompt, then the
    /// swap runs as root. Handles the store-installed (root-owned) old copy.
    private static func replaceWithAdminPrivileges(from source: URL, to destination: URL) throws {
        let command = "rm -rf '\(destination.path)' && cp -pR '\(source.path)' '\(destination.path)'"
        let scriptSource = "do shell script \"\(command)\" with administrator privileges"
        var error: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else {
            throw SelfInstallError.scriptFailed("couldn't build the install script")
        }
        script.executeAndReturnError(&error)
        if let error {
            // -128 = the user cancelled the password prompt.
            if (error[NSAppleScript.errorNumber] as? Int) == -128 { throw SelfInstallError.cancelled }
            throw SelfInstallError.scriptFailed(error[NSAppleScript.errorMessage] as? String ?? "unknown error")
        }
    }
    #endif
}
