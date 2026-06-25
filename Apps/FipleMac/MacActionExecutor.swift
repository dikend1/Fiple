import AppKit
import FipleKit
import Foundation

/// Executes actions on the Mac via `NSWorkspace`. Stateless, hence `Sendable`.
struct MacActionExecutor: ActionExecutor {
    func execute(_ action: Action) async -> ActionResult {
        switch action.kind {
        case let .launchApp(bundleID):
            await launchApp(bundleID: bundleID, actionID: action.id)
        case let .openURL(url):
            await openURL(url, actionID: action.id)
        case let .runShortcut(name):
            await runShortcut(named: name, actionID: action.id)
        }
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
