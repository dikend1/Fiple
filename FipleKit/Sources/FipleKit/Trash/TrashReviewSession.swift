import Foundation

/// Pure state machine behind the iOS swipe deck. All decisions are local until
/// the caller *takes* them: `takeTrashIDs()` when the user empties the basket,
/// `takeKeepIDs()` on commit or when leaving the screen. Undo pops the last
/// uncommitted decision; committed ids are gone from history by construction.
/// The Mac stays authoritative — `reconcile(with:)` re-syncs after every
/// `trashCandidates` push.
public struct TrashReviewSession: Sendable, Equatable {
    private struct Entry: Sendable, Equatable {
        let candidate: TrashCandidate
        let decision: TrashDecision
    }

    private var deck: [TrashCandidate]
    public private(set) var staged: [TrashCandidate] = []
    private var kept: [TrashCandidate] = []
    private var history: [Entry] = []
    /// Decisions already sent to the Mac — still "reviewed" for progress.
    private var committedCount = 0

    public init(candidates: [TrashCandidate]) {
        deck = candidates
    }

    // MARK: Reading

    public var current: TrashCandidate? { deck.first }
    /// Cards behind the current one (underlay rendering + thumbnail prefetch).
    public var upcoming: [TrashCandidate] { Array(deck.dropFirst()) }
    public var keptCount: Int { kept.count }
    public var reviewed: Int { staged.count + kept.count + committedCount }
    public var total: Int { deck.count + reviewed }
    public var canUndo: Bool { !history.isEmpty }

    // MARK: Deciding

    public mutating func swipe(_ decision: TrashDecision) {
        guard !deck.isEmpty else { return }
        let candidate = deck.removeFirst()
        switch decision {
        case .trash: staged.append(candidate)
        case .keep: kept.append(candidate)
        }
        history.append(Entry(candidate: candidate, decision: decision))
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let entry = history.popLast() else { return false }
        switch entry.decision {
        case .trash: staged.removeAll { $0.id == entry.candidate.id }
        case .keep: kept.removeAll { $0.id == entry.candidate.id }
        }
        deck.insert(entry.candidate, at: 0)
        return true
    }

    /// Basket sheet "put it back": undecided again, on top of the deck.
    public mutating func returnToDeck(id: UUID) {
        guard let index = staged.firstIndex(where: { $0.id == id }) else { return }
        let candidate = staged.remove(at: index)
        history.removeAll { $0.candidate.id == id }
        deck.insert(candidate, at: 0)
    }

    // MARK: Committing

    /// Ids to send as one batch `.trash` action. Clears the basket; the
    /// decisions stay counted as reviewed and can no longer be undone.
    public mutating func takeTrashIDs() -> [UUID] {
        let ids = staged.map(\.id)
        committedCount += staged.count
        staged.removeAll()
        history.removeAll { $0.decision == .trash }
        return ids
    }

    /// Ids to send as one batch `.keep` action (on commit or screen exit).
    public mutating func takeKeepIDs() -> [UUID] {
        let ids = kept.map(\.id)
        committedCount += kept.count
        kept.removeAll()
        history.removeAll { $0.decision == .keep }
        return ids
    }

    // MARK: Syncing

    /// Applies a fresh Mac snapshot: candidates the Mac no longer lists vanish
    /// from the deck, basket, and history (evicted or auto-trashed); listed
    /// candidates we've never seen join the end of the deck.
    public mutating func reconcile(with snapshot: [TrashCandidate]) {
        let ids = Set(snapshot.map(\.id))
        deck.removeAll { !ids.contains($0.id) }
        staged.removeAll { !ids.contains($0.id) }
        kept.removeAll { !ids.contains($0.id) }
        history.removeAll { !ids.contains($0.candidate.id) }

        var seen = Set(deck.map(\.id))
        seen.formUnion(staged.map(\.id))
        seen.formUnion(kept.map(\.id))
        for candidate in snapshot where !seen.contains(candidate.id) {
            deck.append(candidate)
        }
    }
}
