#if os(macOS)
import Foundation

/// Moves past-deadline candidates to the **system Trash** — the only
/// destructive action Smart Trash ever takes, and it's always recoverable.
///
/// Every expired candidate is re-validated first (still present, not used
/// since candidacy) so a file touched at the last minute is evicted, never
/// trashed. Run daily and once at launch to catch deadlines missed while the
/// Mac was asleep or off.
public struct TrashDeadlineEnforcer: Sendable {
    public init() {}

    /// Enforces all expired deadlines. Returns the candidates actually moved
    /// to the Trash (for the notification summary).
    @discardableResult
    public func enforce(
        store: TrashCandidateStore, scanner: StaleFileScanner, now: Date
    ) -> [TrashCandidate] {
        // Last-chance re-validation: used/missing files leave the list here.
        scanner.evictUsedOrMissing(store: store, now: now)

        var trashed: [TrashCandidate] = []
        var done: Set<UUID> = []
        for candidate in store.expired(now: now) {
            let url = URL(fileURLWithPath: candidate.path)
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashed.append(candidate)
                done.insert(candidate.id)
            } catch {
                // Couldn't move (permissions, volume gone) — drop it from the
                // list rather than retrying forever; a future scan may re-add.
                done.insert(candidate.id)
            }
        }
        if !done.isEmpty { store.remove(ids: done) }
        return trashed
    }
}
#endif
