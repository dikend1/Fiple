import Foundation

/// Canonical product links, shared by both apps so the macOS host and the iOS
/// remote point at exactly the same legal and support pages.
public enum FipleLinks {
    public static let privacy = URL(string: "https://fiple.app/privacy")!
    public static let terms = URL(string: "https://fiple.app/terms")!
    public static let support = URL(string: "https://fiple.app/support")!
    /// The full Fiple for Mac (Developer ID build with Terminal) — the page the
    /// iOS terminal explainer points at when the paired Mac can't host a shell.
    public static let download = URL(string: "https://fiple.app/download")!
}
