import Foundation

/// What happened when the cache processed a changed file — returned so callers
/// (and tests) can react without inspecting the store.
public enum CacheOutcome: Sendable, Equatable {
    /// Uploaded (or updated) and, if any, these cache copies were evicted.
    case cached(evicted: [String])
    /// Already cached with the same size and modification date — nothing uploaded.
    case unchanged
    /// Not cached because it matched an exclusion rule.
    case excluded
    /// Not cached because of the budget (too large / too old).
    case skipped(SkipReason)
}

/// Orchestrates the read-only mirror: turn a filesystem change into cache
/// operations, honoring exclusions, budget, and eviction.
///
/// It reads disk only through ``FileReading`` and mutates only through
/// ``RemoteFileStore`` — so, by construction, it can never delete or modify an
/// original file (safety invariant). All decisions come from ``CachePlanner``,
/// keeping this layer thin and its behavior testable with in-memory fakes.
public struct RemoteFileCache: Sendable {
    private let store: RemoteFileStore
    private let reader: FileReading
    private let planner: CachePlanner
    private let deviceID: String
    private let ignoredSubfolders: [String]
    /// Optional platform-specific preview generator (Quick Look on the Mac).
    /// When present, its output is uploaded as the file's thumbnail so the phone
    /// can show a real image. Nil in tests / where thumbnails aren't wanted.
    private let thumbnailProvider: (@Sendable (URL) async -> Data?)?

    public init(
        store: RemoteFileStore,
        reader: FileReading,
        planner: CachePlanner = CachePlanner(),
        deviceID: String,
        ignoredSubfolders: [String] = [],
        thumbnailProvider: (@Sendable (URL) async -> Data?)? = nil
    ) {
        self.store = store
        self.reader = reader
        self.planner = planner
        self.deviceID = deviceID
        self.ignoredSubfolders = ignoredSubfolders
        self.thumbnailProvider = thumbnailProvider
    }

    /// Process a created/modified file. Reads its metadata, applies exclusion and
    /// budget, then uploads and evicts as planned. `now` is injected for the age
    /// gate so this stays deterministic.
    ///
    /// Convenience for one-off changes: lists the store itself. Batch callers
    /// (a full reconcile) must use ``handleChange(at:folder:relativePath:snapshot:now:)``
    /// instead, so N files cost one listing rather than N.
    @discardableResult
    public func handleChange(
        at url: URL,
        folder: SourceFolder,
        relativePath: String,
        now: Date
    ) async throws -> CacheOutcome {
        var snapshot = try await store.list()
        return try await handleChange(
            at: url,
            folder: folder,
            relativePath: relativePath,
            snapshot: &snapshot,
            now: now
        )
    }

    /// Snapshot-threading variant for batch reconciles: the caller lists the
    /// store **once** and passes the result through every call; this method
    /// mirrors its own uploads/evictions into `snapshot`, so budget decisions
    /// stay coherent across the batch without re-querying CloudKit per file.
    @discardableResult
    public func handleChange(
        at url: URL,
        folder: SourceFolder,
        relativePath: String,
        snapshot: inout [RemoteFile],
        now: Date
    ) async throws -> CacheOutcome {
        let fileName = url.lastPathComponent
        if FileExclusion.isExcluded(
            fileName: fileName,
            relativePath: relativePath,
            ignoredSubfolders: ignoredSubfolders
        ) {
            return .excluded
        }

        let meta = try reader.metadata(at: url)
        let candidate = RemoteFile(
            fileName: fileName,
            sourceFolder: folder,
            relativePath: relativePath,
            sizeBytes: meta.sizeBytes,
            modifiedAt: meta.modifiedAt,
            contentType: meta.contentType,
            sourceDeviceID: deviceID
        )

        let current = snapshot.first { $0.recordName == candidate.recordName }

        // Same size + modification date as the cached copy → re-uploading would
        // re-send the full payload for nothing. Saving one file must never cost
        // re-uploading the whole corpus.
        if let current, Self.isUnchanged(current, candidate) {
            return .unchanged
        }

        // A pinned file bypasses fresh admission entirely: re-upload in place,
        // never subject to eviction.
        if let current, current.isPinned {
            var pinned = candidate
            pinned.isPinned = true
            let data = try reader.readData(at: url)
            let thumb = await thumbnailProvider?(url)
            try await store.upload(pinned, payload: data, thumbnail: thumb)
            Self.apply(upserting: pinned, evicting: [], to: &snapshot)
            return .cached(evicted: [])
        }

        let plan = planner.planAdmission(of: candidate, existing: snapshot, now: now)
        guard plan.admit else {
            return .skipped(plan.skip ?? .tooLarge)
        }

        let data = try reader.readData(at: url)
        let thumb = await thumbnailProvider?(url)
        try await store.upload(candidate, payload: data, thumbnail: thumb)
        if !plan.evict.isEmpty {
            try await store.delete(recordNames: plan.evict)
        }
        Self.apply(upserting: candidate, evicting: plan.evict, to: &snapshot)
        return .cached(evicted: plan.evict)
    }

    /// Whether the cached copy already matches the on-disk file. Dates are
    /// compared with a small tolerance because CloudKit round-trips them with
    /// less precision than APFS mtimes — exact equality would re-upload forever.
    private static func isUnchanged(_ current: RemoteFile, _ candidate: RemoteFile) -> Bool {
        current.sizeBytes == candidate.sizeBytes
            && abs(current.modifiedAt.timeIntervalSince(candidate.modifiedAt)) < 0.01
    }

    /// Mirror an upload/eviction into the caller's snapshot so subsequent batch
    /// decisions see the store as it now is.
    private static func apply(
        upserting file: RemoteFile,
        evicting: [String],
        to snapshot: inout [RemoteFile]
    ) {
        snapshot.removeAll { evicting.contains($0.recordName) || $0.recordName == file.recordName }
        snapshot.append(file)
    }

    /// A file was deleted from disk → drop its cache copy (never the reverse).
    public func handleDeletion(
        folder: SourceFolder,
        relativePath: String
    ) async throws {
        let recordName = RemoteFile.recordName(
            deviceID: deviceID,
            folder: folder,
            relativePath: relativePath
        )
        try await store.delete(recordNames: [recordName])
    }

    /// Pin a file if the pinned budget allows. Returns false (and changes
    /// nothing) when the favorites limit is reached.
    @discardableResult
    public func pin(recordName: String) async throws -> Bool {
        let existing = try await store.list()
        guard let file = existing.first(where: { $0.recordName == recordName }) else {
            return false
        }
        guard planner.canPin(file, existing: existing) else { return false }
        try await store.setPinned(recordName: recordName, true)
        return true
    }

    /// Unpin a file, returning it to the fresh pool's budget.
    public func unpin(recordName: String) async throws {
        try await store.setPinned(recordName: recordName, false)
    }

    /// Turn the feature off: purge every cache copy. Originals are untouched.
    public func disableAndPurge() async throws {
        try await store.purgeAll()
    }
}
