import Foundation

/// Finds stale files in the granted folders and reconciles the candidate list.
///
/// A file is stale when it hasn't been opened for `stalenessThreshold` (falling
/// back to the modification date when the system has no access date). The scan
/// also evicts candidates whose file was used again, changed, or disappeared —
/// the "used again → leaves the list" guarantee. Pure filesystem + store logic;
/// no UI, no network. `now` is injected so tests control time.
public struct StaleFileScanner: Sendable {
    public var stalenessThreshold: TimeInterval
    public var reviewWindow: TimeInterval

    public init(
        stalenessThreshold: TimeInterval = 60 * 86_400,
        reviewWindow: TimeInterval = 7 * 86_400
    ) {
        self.stalenessThreshold = stalenessThreshold
        self.reviewWindow = reviewWindow
    }

    /// One pass: evict stale-no-longer candidates, then add newly stale files.
    /// Returns the number of candidates added.
    @discardableResult
    public func scan(folders: [URL], store: TrashCandidateStore, now: Date) -> Int {
        evictUsedOrMissing(store: store, now: now)

        var added = 0
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .contentAccessDateKey, .contentModificationDateKey, .fileSizeKey,
        ]
        for folder in folders {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )) ?? []
            for url in entries {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let lastUsed = Self.lastUsed(values)
                else { continue }
                guard now.timeIntervalSince(lastUsed) >= stalenessThreshold else { continue }
                if store.add(
                    path: url.path, sizeBytes: Int64(values.fileSize ?? 0),
                    lastOpened: lastUsed, now: now, reviewWindow: reviewWindow
                ) != nil { added += 1 }
            }
        }
        return added
    }

    /// Drops candidates whose file was opened/modified after candidacy or no
    /// longer exists at the recorded path. Also run right before deadline
    /// enforcement so a just-used file is never trashed.
    public func evictUsedOrMissing(store: TrashCandidateStore, now: Date) {
        var evicted: Set<UUID> = []
        for candidate in store.candidates {
            let url = URL(fileURLWithPath: candidate.path)
            guard let values = try? url.resourceValues(
                forKeys: [.contentAccessDateKey, .contentModificationDateKey]
            ) else {
                evicted.insert(candidate.id) // gone or unreadable → out
                continue
            }
            if let used = Self.lastUsed(values), used > candidate.addedAt {
                evicted.insert(candidate.id)
            }
        }
        if !evicted.isEmpty { store.remove(ids: evicted) }
    }

    /// Most recent of access/modification date — either counts as "used".
    private static func lastUsed(_ values: URLResourceValues) -> Date? {
        switch (values.contentAccessDate, values.contentModificationDate) {
        case let (a?, m?): return max(a, m)
        case let (a?, nil): return a
        case let (nil, m?): return m
        case (nil, nil): return nil
        }
    }
}
