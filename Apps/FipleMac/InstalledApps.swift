import AppKit
import Foundation

/// A discovered application the user can pick when building a `launchApp` action.
struct InstalledApp: Identifiable, Hashable, Sendable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let url: URL
}

enum InstalledApps {
    private static let searchPaths = [
        "/Applications",
        "/System/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    /// Enumerates installed `.app` bundles and reads their bundle ids, sorted by name.
    static func all() -> [InstalledApp] {
        let fm = FileManager.default
        var seen = Set<String>()
        var apps: [InstalledApp] = []

        for path in searchPaths {
            guard let entries = try? fm.contentsOfDirectory(atPath: path) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let url = URL(fileURLWithPath: path).appendingPathComponent(entry)
                guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier,
                      seen.insert(bundleID).inserted else { continue }
                let name = fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                apps.append(InstalledApp(bundleID: bundleID, name: name, url: url))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
