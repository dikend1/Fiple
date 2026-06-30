import Foundation

/// Pure free-tier gating for the iOS remote: the first `freeLimit` items in an
/// ordered list are free, the rest are locked behind Fiple Pro. Generic over any
/// identifiable list, so it gates both the Fiple Bar (quick-launch actions) and
/// the workspace presets with one rule. Lives in FipleKit only so it is
/// unit-testable; the Mac never calls it (gating is an iOS-presentation concern —
/// see `adr/0003-monetization-entitlement-dependency`).
public enum FreeTierGate {
    /// Items usable without Fiple Pro by default.
    public static let defaultFreeLimit = 8

    /// The ids of items locked behind Fiple Pro, given an ordered list and the
    /// current Pro state. Being Pro — or having a list within the free limit —
    /// locks nothing.
    ///
    /// - Parameters:
    ///   - items: the list in display order; the first `freeLimit` stay free.
    ///   - freeLimit: how many are free; negative values are treated as `0`.
    ///   - isPro: whether Fiple Pro is active (honored from cache when offline).
    public static func lockedIDs<T: Identifiable>(
        _ items: [T],
        freeLimit: Int = defaultFreeLimit,
        isPro: Bool
    ) -> Set<T.ID> {
        guard !isPro else { return [] }
        let limit = max(0, freeLimit)
        guard items.count > limit else { return [] }
        return Set(items.dropFirst(limit).map(\.id))
    }
}
