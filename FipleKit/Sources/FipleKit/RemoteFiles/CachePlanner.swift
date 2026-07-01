import Foundation

/// Why a candidate file was not admitted to the fresh cache pool.
public enum SkipReason: Sendable, Equatable {
    /// Larger than the per-file cap. Surfaced to the user, not treated as an error.
    case tooLarge
    /// Older than the fresh pool's age gate.
    case tooOld
}

/// The decision for one candidate file: whether to cache it and which existing
/// cache copies to evict to make room.
public struct AdmissionPlan: Sendable, Equatable {
    public var admit: Bool
    public var skip: SkipReason?
    /// `recordName`s of *cache copies* to remove from CloudKit — never disk
    /// paths. Eviction only ever touches the cloud cache (safety invariant).
    public var evict: [String]

    public init(admit: Bool, skip: SkipReason? = nil, evict: [String] = []) {
        self.admit = admit
        self.skip = skip
        self.evict = evict
    }

    static let rejectedTooLarge = AdmissionPlan(admit: false, skip: .tooLarge)
    static let rejectedTooOld = AdmissionPlan(admit: false, skip: .tooOld)
}

/// Pure policy engine deciding what the Mac keeps in the private CloudKit cache.
///
/// Two independent pools:
/// - **fresh** — auto-managed recent files, subject to age/count/size and
///   oldest-first eviction;
/// - **pinned** — favorites, exempt from fresh eviction, bounded by their own
///   budget.
///
/// The pools never compete: pinned files are ignored when planning fresh
/// eviction, and fresh files never count against the pinned budget. Everything
/// here is deterministic and side-effect-free — `now` is injected — so it is
/// fully unit-testable without a filesystem or iCloud.
public struct CachePlanner: Sendable, Equatable {
    public var freshBudget: CacheBudget
    public var pinnedBudget: CacheBudget

    public init(
        freshBudget: CacheBudget = .freshDefault,
        pinnedBudget: CacheBudget = .pinnedDefault
    ) {
        self.freshBudget = freshBudget
        self.pinnedBudget = pinnedBudget
    }

    /// Plan admission of a *fresh* (non-pinned) candidate into the current cache.
    ///
    /// - Parameters:
    ///   - candidate: the changed/created file being considered.
    ///   - existing: the full current cache (both pools). Pinned entries are
    ///     ignored for eviction and budgeting.
    ///   - now: current instant, for the age gate.
    /// - Returns: whether to upload the candidate and which fresh cache copies to
    ///   evict first (oldest by `modifiedAt`).
    public func planAdmission(
        of candidate: RemoteFile,
        existing: [RemoteFile],
        now: Date
    ) -> AdmissionPlan {
        if candidate.sizeBytes > freshBudget.maxFileBytes { return .rejectedTooLarge }
        if now.timeIntervalSince(candidate.modifiedAt) > freshBudget.maxAge {
            return .rejectedTooOld
        }

        // The candidate replaces any existing record with the same identity, so
        // exclude it from the pool it's being weighed against (an update, not an
        // addition). Pinned files are off-limits to fresh eviction.
        let pool = existing
            .filter { !$0.isPinned && $0.recordName != candidate.recordName }
            .sorted { $0.modifiedAt < $1.modifiedAt } // oldest first

        var count = pool.count + 1 // + candidate
        var bytes = pool.reduce(candidate.sizeBytes) { $0 + $1.sizeBytes }
        var evict: [String] = []
        var index = 0
        while (count > freshBudget.maxCount || bytes > freshBudget.maxTotalBytes),
              index < pool.count {
            let victim = pool[index]
            evict.append(victim.recordName)
            count -= 1
            bytes -= victim.sizeBytes
            index += 1
        }

        return AdmissionPlan(admit: true, evict: evict)
    }

    /// Whether `file` can be pinned without exceeding the pinned budget.
    ///
    /// A file already pinned counts as itself (re-pin is a no-op that always
    /// fits). Returns false at the count cap, the total-size cap, or the per-file
    /// cap — the caller shows "Favorites limit reached".
    public func canPin(_ file: RemoteFile, existing: [RemoteFile]) -> Bool {
        if file.sizeBytes > pinnedBudget.maxFileBytes { return false }
        let others = existing.filter { $0.isPinned && $0.recordName != file.recordName }
        if others.count + 1 > pinnedBudget.maxCount { return false }
        let total = others.reduce(file.sizeBytes) { $0 + $1.sizeBytes }
        if total > pinnedBudget.maxTotalBytes { return false }
        return true
    }
}
