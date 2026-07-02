import Foundation

/// Decides which files never enter the cache, independent of budget.
///
/// Keeps system noise, application/installer bundles, and user-ignored subfolders
/// out of the mirror so the phone shows real documents, not `.DS_Store` or a
/// 5 GB `.photoslibrary`.
public enum FileExclusion {
    /// Extensions treated as opaque bundles / installers / packages — never
    /// useful as a single downloadable file on the phone. Lowercased, no dot.
    public static let excludedExtensions: Set<String> = [
        "app", "dmg", "pkg", "framework", "bundle", "photoslibrary",
        "xcodeproj", "xcworkspace", "download", "part", "crdownload",
    ]

    /// Credential-bearing extensions that must **never** reach the cloud cache,
    /// whatever the user configures — leaking a private key or keychain export
    /// through a compromised Apple ID would be far worse than a missing file.
    /// Note `key` also blocks Keynote decks: an accepted false positive, since
    /// there is no cheap way to tell a presentation from a private key by name.
    public static let sensitiveExtensions: Set<String> = [
        "pem", "p12", "key", "keychain", "mobileprovision", "p8",
        "cer", "der", "pfx", "ovpn", "kdbx", "wallet",
    ]

    /// Whether a file should be excluded from the cache.
    ///
    /// - Parameters:
    ///   - fileName: the last path component (e.g. `report.pdf`).
    ///   - relativePath: path within its source folder (e.g. `Reports/report.pdf`).
    ///   - ignoredSubfolders: relative subfolder prefixes the user excluded
    ///     (e.g. `Private`, `Work/Secret`). Matched case-insensitively on a path
    ///     boundary so `Work` doesn't accidentally match `Workshop`.
    public static func isExcluded(
        fileName: String,
        relativePath: String,
        ignoredSubfolders: [String] = []
    ) -> Bool {
        // Hidden / system files (dotfiles, .DS_Store).
        if fileName.hasPrefix(".") { return true }

        // Opaque bundles / installers, and credential material, by extension.
        let ext = (fileName as NSString).pathExtension.lowercased()
        if !ext.isEmpty, excludedExtensions.contains(ext) || sensitiveExtensions.contains(ext) {
            return true
        }

        // User-ignored subfolders, matched on a path-component boundary.
        let normalized = relativePath.lowercased()
        for raw in ignoredSubfolders {
            let prefix = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !prefix.isEmpty else { continue }
            if normalized == prefix
                || normalized.hasPrefix(prefix + "/") {
                return true
            }
        }
        return false
    }
}
