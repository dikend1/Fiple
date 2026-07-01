import Foundation

/// Limits governing how much the Mac keeps mirrored in the private CloudKit
/// cache. Two independent budgets exist — one for the auto-managed *fresh* pool
/// and one for *pinned* favorites — so favorites can never be crowded out by new
/// files, and vice versa (see ``CachePlanner``).
public struct CacheBudget: Sendable, Equatable {
    /// Files older than this (by last-modified) are not admitted to the fresh
    /// pool. Use `.greatestFiniteMagnitude` to disable the age gate (pinned pool).
    public var maxAge: TimeInterval
    /// Maximum number of files in this pool.
    public var maxCount: Int
    /// Maximum total bytes across the pool.
    public var maxTotalBytes: Int64
    /// Maximum size of any single file; larger files are skipped, not an error.
    public var maxFileBytes: Int64

    public init(
        maxAge: TimeInterval,
        maxCount: Int,
        maxTotalBytes: Int64,
        maxFileBytes: Int64
    ) {
        self.maxAge = maxAge
        self.maxCount = maxCount
        self.maxTotalBytes = maxTotalBytes
        self.maxFileBytes = maxFileBytes
    }

    private static let day: TimeInterval = 24 * 60 * 60
    private static let mb: Int64 = 1024 * 1024
    private static let gb: Int64 = 1024 * 1024 * 1024

    /// Defaults for the auto-managed recent-files pool: ≤ 30 days, ≤ 200 files,
    /// ≤ 2 GB total, ≤ 100 MB per file.
    public static let freshDefault = CacheBudget(
        maxAge: 30 * day,
        maxCount: 200,
        maxTotalBytes: 2 * gb,
        maxFileBytes: 100 * mb
    )

    /// Defaults for pinned favorites: no age gate, ≤ 50 files, ≤ 1 GB total,
    /// ≤ 100 MB per file.
    public static let pinnedDefault = CacheBudget(
        maxAge: .greatestFiniteMagnitude,
        maxCount: 50,
        maxTotalBytes: 1 * gb,
        maxFileBytes: 100 * mb
    )
}
