import Foundation

/// Execution-time safety policy for actions arriving over the wire.
///
/// The transport authenticates *who* may send actions (pairing), but a paired
/// peer can still send an arbitrary ``Action``. This policy is the second gate:
/// it constrains *what* an action is allowed to do before the Mac executes it.
public enum ActionPolicy {
    /// URL schemes an `openURL` action may use. Restricted to web schemes so a
    /// peer cannot ask the Mac to open `file://` (arbitrary local files, which
    /// can mean code execution via the default handler) or app-specific custom
    /// schemes.
    public static let allowedURLSchemes: Set<String> = ["http", "https"]

    /// Whether an `openURL` action targeting `url` is allowed to run.
    public static func allowsOpening(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return allowedURLSchemes.contains(scheme)
    }
}
