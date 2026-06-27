import AppKit
import FipleKit
import Foundation

/// Executes actions on the Mac via `NSWorkspace`. Stateless, hence `Sendable`.
struct MacActionExecutor: ActionExecutor {
    func execute(_ action: Action) async -> ActionResult {
        FipleLog.execution.info("executing: \(action.displayLabel)")
        let result: ActionResult
        switch action.kind {
        case let .launchApp(bundleID):
            result = await launchApp(bundleID: bundleID, actionID: action.id)
        case let .openURL(url):
            result = await openURL(url, actionID: action.id)
        case let .runShortcut(name):
            result = await runShortcut(named: name, actionID: action.id)
        }
        if result.ok {
            FipleLog.execution.info("ok: \(action.displayLabel)")
        } else {
            FipleLog.execution.error("failed: \(action.displayLabel) — \(result.error ?? "unknown error")")
        }
        return result
    }

    private func launchApp(bundleID: String, actionID: UUID) async -> ActionResult {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return .failure(actionID, "App not installed: \(bundleID)")
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            return .success(actionID)
        } catch {
            return .failure(actionID, error.localizedDescription)
        }
    }

    private func openURL(_ url: URL, actionID: UUID) async -> ActionResult {
        // A paired peer can send any URL; only open web links. This blocks
        // file:// (arbitrary local files → possible code execution via the
        // default handler) and app-specific custom schemes.
        guard ActionPolicy.allowsOpening(url) else {
            FipleLog.execution.error("blocked URL scheme: \(url.scheme ?? "none")")
            return .failure(actionID, "Blocked URL: only http and https are allowed")
        }
        do {
            _ = try await NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
            return .success(actionID)
        } catch {
            return .failure(actionID, error.localizedDescription)
        }
    }

    /// Runs an Apple Shortcut by name via the `shortcuts://` URL scheme. Opening
    /// a URL is permitted under the App Sandbox, so this needs no file-system
    /// access. The shortcut itself (created by the user in the Shortcuts app)
    /// carries whatever file/script permissions it requires.
    private func runShortcut(named name: String, actionID: UUID) async -> ActionResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(actionID, "Shortcut name is empty")
        }
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: trimmed)]
        guard let url = components.url else {
            return .failure(actionID, "Invalid shortcut name: \(trimmed)")
        }
        do {
            _ = try await NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
            return .success(actionID)
        } catch {
            return .failure(actionID, error.localizedDescription)
        }
    }
}
