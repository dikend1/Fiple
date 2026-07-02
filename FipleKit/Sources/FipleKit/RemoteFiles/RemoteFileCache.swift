import Foundation

/// What happened when the cache processed a changed file — returned so callers
/// (and tests) can react without inspecting the store.
public enum CacheOutcome: Sendable, Equatable {
    /// Uploaded (or updated) and, if any, these cache copies were evicted.
    case cached(evicted: [String])
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
    @discardableResult
    public func handleChange(
        at url: URL,
        folder: SourceFolder,
        relativePath: String,
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

        let existing = try await store.list()

        // A pinned file bypasses fresh admission entirely: re-upload in place,
        // never subject to eviction.
        if let current = existing.first(where: { $0.recordName == candidate.recordName }),
           current.isPinned {
            var pinned = candidate
            pinned.isPinned = true
            let data = try reader.readData(at: url)
            let thumb = await thumbnailProvider?(url)
            try await store.upload(pinned, payload: data, thumbnail: thumb)
            return .cached(evicted: [])
        }

        let plan = planner.planAdmission(of: candidate, existing: existing, now: now)
        guard plan.admit else {
            return .skipped(plan.skip ?? .tooLarge)
        }

        let data = try reader.readData(at: url)
        let thumb = await thumbnailProvider?(url)
        try await store.upload(candidate, payload: data, thumbnail: thumb)
        if !plan.evict.isEmpty {
            try await store.delete(recordNames: plan.evict)
        }
        return .cached(evicted: plan.evict)
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
