import Foundation

/// Parses user-typed text into a web URL for an `openURL` action.
///
/// People type `github.com`, not `https://github.com`. A bare host has no URL
/// scheme, and an action with a scheme-less URL was previously discarded on save
/// (and would be blocked by ``ActionPolicy`` at run time anyway). This defaults a
/// missing scheme to `https`, so the everyday input just works, and validates the
/// result against the same web-only policy used at execution — a saved URL is
/// therefore always runnable.
public enum URLInput {
    /// A web URL parsed from `text`, defaulting a missing scheme to `https`, or
    /// nil when the text can't form an http/https URL with a host.
    public static func webURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // An explicit scheme is honoured only if it's a web one; a non-web scheme
        // (file://, ftp://, custom://) is rejected rather than wrapped. A bare
        // host with no scheme — the common case, `github.com` — gets https.
        let candidate: String
        if let scheme = URL(string: trimmed)?.scheme {
            guard ActionPolicy.allowedURLSchemes.contains(scheme.lowercased()) else { return nil }
            candidate = trimmed
        } else {
            candidate = "https://" + trimmed
        }

        guard let url = URL(string: candidate),
              ActionPolicy.allowsOpening(url),
              let host = url.host(), !host.isEmpty else { return nil }
        return url
    }
}
