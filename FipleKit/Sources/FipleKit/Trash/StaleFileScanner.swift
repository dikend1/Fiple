import Foundation
#if os(macOS)
import CoreServices
#endif

/// Finds stale files in the granted folders and reconciles the candidate list.
///
/// A file is stale when it hasn't been *meaningfully used* for
/// `stalenessThreshold`. "Used" is Finder's truth — the most recent of
/// Spotlight's last-open date (`kMDItemLastUsedDate`), the modification date,
/// and the date the file was added to its folder — NOT the POSIX access date:
/// any process that merely reads a file (Spotlight indexing, backups, and
/// Fiple's own QuickLook thumbnailer feeding the phone's review grid) bumps
/// atime, which would evict every candidate the moment it was previewed and
/// then hide it from re-scans for a whole threshold period. The added-to-folder
/// date also protects freshly downloaded archives that carry old upstream
/// modification dates.
///
/// The scan also evicts candidates whose file was used again, changed,
/// disappeared, or no longer qualifies under the current threshold — the
/// "used again → leaves the list" guarantee. Pure filesystem + store logic;
/// no UI, no network. `now` and the date signal are injectable so tests
/// control time.
public struct StaleFileScanner: Sendable {
    public var stalenessThreshold: TimeInterval
    public var reviewWindow: TimeInterval
    /// Returns when a file was last meaningfully used, or nil to skip it.
    /// Defaults to ``finderLastUsed``; injectable so tests control dates
    /// (a real file created in a test is always "just used" by Finder truth).
    public var lastUsed: @Sendable (URL, URLResourceValues) -> Date?

    public init(
        stalenessThreshold: TimeInterval = 60 * 86_400,
        reviewWindow: TimeInterval = 7 * 86_400,
        lastUsed: @escaping @Sendable (URL, URLResourceValues) -> Date? = StaleFileScanner.finderLastUsed
    ) {
        self.stalenessThreshold = stalenessThreshold
        self.reviewWindow = reviewWindow
        self.lastUsed = lastUsed
    }

    /// The resource keys the scan fetches and hands to `lastUsed`.
    private static let dateKeys: Set<URLResourceKey> = [
        .contentModificationDateKey, .addedToDirectoryDateKey,
    ]

    /// Finder's "Last Opened" semantics: the most recent of the Spotlight
    /// last-used date, the modification date, and the added-to-folder date.
    /// Content *reads* (previews, indexing, backups) move none of these.
    public static let finderLastUsed: @Sendable (URL, URLResourceValues) -> Date? = { url, values in
        var dates: [Date] = []
        if let modified = values.contentModificationDate { dates.append(modified) }
        if let added = values.addedToDirectoryDate { dates.append(added) }
        #if os(macOS)
        if let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
           let used = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date {
            dates.append(used)
        }
        #endif
        return dates.max()
    }

    /// One pass: evict stale-no-longer candidates, then add newly stale files.
    /// Returns the number of candidates added.
    @discardableResult
    public func scan(folders: [URL], store: TrashCandidateStore, now: Date) -> Int {
        evictUsedOrMissing(store: store, now: now)

        var added = 0
        let keys = Self.dateKeys.union([.isRegularFileKey, .fileSizeKey])
        for folder in folders {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )) ?? []
            for url in entries {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let lastUsed = lastUsed(url, values)
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

    /// Drops candidates that no longer qualify: the file was opened/modified
    /// after candidacy, no longer exists at the recorded path, or isn't stale
    /// under the *current* threshold (the user raised it — e.g. 15 → 90 days —
    /// so files listed by the old policy must leave immediately, not linger
    /// toward a deadline they no longer deserve). Also run right before
    /// deadline enforcement so a just-used file is never trashed.
    public func evictUsedOrMissing(store: TrashCandidateStore, now: Date) {
        var evicted: Set<UUID> = []
        for candidate in store.candidates {
            let url = URL(fileURLWithPath: candidate.path)
            guard let values = try? url.resourceValues(forKeys: Self.dateKeys) else {
                evicted.insert(candidate.id) // gone or unreadable → out
                continue
            }
            guard let used = lastUsed(url, values) else { continue }
            if used > candidate.addedAt {
                evicted.insert(candidate.id)
            } else if now.timeIntervalSince(used) < stalenessThreshold {
                // Under an unchanged threshold this can't fire (staleness only
                // grows while unused) — it catches a raised threshold.
                evicted.insert(candidate.id)
            }
        }
        if !evicted.isEmpty { store.remove(ids: evicted) }
    }
}
