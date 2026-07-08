#if os(macOS)
import Foundation

/// Applies a phone review decision server-authoritatively: ids are resolved
/// against the Mac's own candidate store; anything unknown is reported back,
/// never acted on. `trash` re-checks the file wasn't used after candidacy —
/// the same guarantee deadline enforcement gives.
public struct TrashReviewHandler: Sendable {
    public init() {}

    /// Returns the typed result the server sends back (`trashActionResult`).
    public func apply(
        ids: [UUID], decision: TrashDecision, store: TrashCandidateStore, scanner: StaleFileScanner, now: Date
    ) -> ServerMessage {
        // Sync with reality first so a just-used file can't be trashed by a
        // stale snapshot on the phone.
        scanner.evictUsedOrMissing(store: store, now: now)

        var resolved: [TrashCandidate] = []
        var unknown: [UUID] = []
        for id in ids {
            if let candidate = store.candidate(id: id) { resolved.append(candidate) }
            else { unknown.append(id) }
        }

        switch decision {
        case .keep:
            store.keep(ids: Set(resolved.map(\.id)))
            return .trashActionResult(trashed: [], kept: resolved.map(\.id), unknown: unknown)
        case .trash:
            var trashed: [UUID] = []
            var done: Set<UUID> = []
            for candidate in resolved {
                let url = URL(fileURLWithPath: candidate.path)
                if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
                    trashed.append(candidate.id)
                } else {
                    unknown.append(candidate.id) // vanished between checks
                }
                done.insert(candidate.id)
            }
            store.remove(ids: done)
            return .trashActionResult(trashed: trashed, kept: [], unknown: unknown)
        }
    }
}
#endif
