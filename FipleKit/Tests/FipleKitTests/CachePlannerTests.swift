import Foundation
import Testing
@testable import FipleKit

@Suite("Cache planner — budget, eviction, pinning")
struct CachePlannerTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let mb: Int64 = 1024 * 1024

    /// A tiny fresh budget so tests are readable; pinned uses defaults unless a
    /// test overrides it.
    private func planner(count: Int = 3, totalMB: Int64 = 100, fileMB: Int64 = 50) -> CachePlanner {
        CachePlanner(
            freshBudget: CacheBudget(
                maxAge: 30 * 24 * 60 * 60,
                maxCount: count,
                maxTotalBytes: totalMB * mb,
                maxFileBytes: fileMB * mb
            ),
            pinnedBudget: .pinnedDefault
        )
    }

    @Test("a fitting fresh file is admitted with no eviction")
    func admitWithoutEviction() {
        let plan = planner().planAdmission(
            of: .fixture(name: "a.txt", size: mb, modifiedAt: t0),
            existing: [],
            now: t0
        )
        #expect(plan == AdmissionPlan(admit: true, evict: []))
    }

    @Test("over the count budget, the oldest fresh file is evicted first")
    func evictsOldestByCount() {
        let existing = [
            RemoteFile.fixture(name: "old.txt", path: "old.txt", size: mb, modifiedAt: t0.addingTimeInterval(-300)),
            RemoteFile.fixture(name: "mid.txt", path: "mid.txt", size: mb, modifiedAt: t0.addingTimeInterval(-200)),
            RemoteFile.fixture(name: "new.txt", path: "new.txt", size: mb, modifiedAt: t0.addingTimeInterval(-100)),
        ]
        let oldest = existing[0].recordName
        let plan = planner(count: 3).planAdmission(
            of: .fixture(name: "fresh.txt", path: "fresh.txt", size: mb, modifiedAt: t0),
            existing: existing,
            now: t0
        )
        #expect(plan.admit)
        #expect(plan.evict == [oldest])
    }

    @Test("over the size budget, evicts oldest until total fits")
    func evictsBySize() {
        // total budget 100 MB, three 40 MB files already cached → 120 MB; adding
        // one more 40 MB must evict enough oldest copies to get under 100 MB.
        let existing = [
            RemoteFile.fixture(name: "o1", path: "o1", size: 40 * mb, modifiedAt: t0.addingTimeInterval(-300)),
            RemoteFile.fixture(name: "o2", path: "o2", size: 40 * mb, modifiedAt: t0.addingTimeInterval(-200)),
        ]
        let plan = planner(count: 99, totalMB: 100).planAdmission(
            of: .fixture(name: "n", path: "n", size: 40 * mb, modifiedAt: t0),
            existing: existing,
            now: t0
        )
        // keep candidate (40) + o2 (40) = 80 ≤ 100; evict o1.
        #expect(plan.evict == [existing[0].recordName])
    }

    @Test("a file larger than the per-file cap is skipped")
    func skipsTooLarge() {
        let plan = planner(fileMB: 50).planAdmission(
            of: .fixture(name: "huge.mov", size: 60 * mb, modifiedAt: t0),
            existing: [],
            now: t0
        )
        #expect(plan == .rejectedTooLarge)
    }

    @Test("a file older than the age gate is skipped")
    func skipsTooOld() {
        let old = t0.addingTimeInterval(-40 * 24 * 60 * 60) // 40 days old
        let plan = planner().planAdmission(
            of: .fixture(name: "ancient.txt", size: mb, modifiedAt: old),
            existing: [],
            now: t0
        )
        #expect(plan == .rejectedTooOld)
    }

    @Test("pinned files are never evicted and don't count against the fresh budget")
    func pinnedExemptFromEviction() {
        // Two pinned files older than everything; fresh count budget is 1.
        let existing = [
            RemoteFile.fixture(name: "p1", path: "p1", size: mb, modifiedAt: t0.addingTimeInterval(-999), pinned: true),
            RemoteFile.fixture(name: "p2", path: "p2", size: mb, modifiedAt: t0.addingTimeInterval(-998), pinned: true),
        ]
        let plan = planner(count: 1).planAdmission(
            of: .fixture(name: "fresh", path: "fresh", size: mb, modifiedAt: t0),
            existing: existing,
            now: t0
        )
        #expect(plan.admit)
        #expect(plan.evict.isEmpty) // pinned p1/p2 untouched; candidate fits (1 fresh slot)
    }

    @Test("updating an existing file doesn't double-count it in the budget")
    func updateDoesNotSelfEvict() {
        let file = RemoteFile.fixture(name: "a", path: "a", size: mb, modifiedAt: t0.addingTimeInterval(-10))
        let updated = RemoteFile.fixture(name: "a", path: "a", size: mb, modifiedAt: t0) // same recordName
        let plan = planner(count: 1).planAdmission(of: updated, existing: [file], now: t0)
        #expect(plan.admit)
        #expect(plan.evict.isEmpty)
    }

    @Test("canPin enforces the separate favorites count budget")
    func canPinCountLimit() {
        let p = CachePlanner(
            freshBudget: .freshDefault,
            pinnedBudget: CacheBudget(maxAge: .greatestFiniteMagnitude, maxCount: 2, maxTotalBytes: 10 * mb, maxFileBytes: 5 * mb)
        )
        let existing = [
            RemoteFile.fixture(name: "p1", path: "p1", size: mb, modifiedAt: t0, pinned: true),
            RemoteFile.fixture(name: "p2", path: "p2", size: mb, modifiedAt: t0, pinned: true),
        ]
        let candidate = RemoteFile.fixture(name: "p3", path: "p3", size: mb, modifiedAt: t0)
        #expect(p.canPin(candidate, existing: existing) == false)
    }

    @Test("canPin enforces the favorites total-size budget")
    func canPinSizeLimit() {
        let p = CachePlanner(
            freshBudget: .freshDefault,
            pinnedBudget: CacheBudget(maxAge: .greatestFiniteMagnitude, maxCount: 50, maxTotalBytes: 10 * mb, maxFileBytes: 100 * mb)
        )
        let existing = [
            RemoteFile.fixture(name: "p1", path: "p1", size: 8 * mb, modifiedAt: t0, pinned: true),
        ]
        let candidate = RemoteFile.fixture(name: "p2", path: "p2", size: 5 * mb, modifiedAt: t0)
        #expect(p.canPin(candidate, existing: existing) == false) // 8 + 5 > 10
    }

    @Test("re-pinning an already-pinned file always fits")
    func canRepinExisting() {
        let p = CachePlanner(
            freshBudget: .freshDefault,
            pinnedBudget: CacheBudget(maxAge: .greatestFiniteMagnitude, maxCount: 1, maxTotalBytes: mb, maxFileBytes: mb)
        )
        let file = RemoteFile.fixture(name: "p1", path: "p1", size: mb, modifiedAt: t0, pinned: true)
        #expect(p.canPin(file, existing: [file]))
    }
}
