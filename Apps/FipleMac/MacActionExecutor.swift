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
        case let .openFile(path, openWith):
            await openFile(path: path, openWith: openWith, actionID: action.id)
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

    private func openFile(path: String, openWith: String?, actionID: UUID) async -> ActionResult {
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            return .failure(actionID, "File not found: \(path)")
        }
        let config = NSWorkspace.OpenConfiguration()
        do {
            if let openWith,
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: openWith) {
                _ = try await NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config)
            } else {
                _ = try await NSWorkspace.shared.open(fileURL, configuration: config)
            }
            return .success(actionID)
        } catch {
            return .failure(actionID, error.localizedDescription)
        }
    }
}
