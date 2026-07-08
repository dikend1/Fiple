import Foundation

/// One stale file proposed for cleanup. The file stays untouched on disk while
/// it sits in the candidate list; only the metadata below travels to the phone.
public struct TrashCandidate: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    /// Absolute path at candidacy time; re-validated before any move.
    public let path: String
    public let sizeBytes: Int64
    public let lastOpened: Date
    public let addedAt: Date
    /// Unreviewed past this instant → auto-move to the system Trash.
    public let deadline: Date

    public init(
        id: UUID = UUID(),
        path: String,
        sizeBytes: Int64,
        lastOpened: Date,
        addedAt: Date,
        deadline: Date
    ) {
        self.id = id
        self.path = path
        self.sizeBytes = sizeBytes
        self.lastOpened = lastOpened
        self.addedAt = addedAt
        self.deadline = deadline
    }

    public var fileName: String { (path as NSString).lastPathComponent }
}

/// The Mac-side source of truth for Smart Trash: pending candidates plus the
/// permanent keep-list ("never propose this file again"). Persisted as JSON at
/// the injected URL so tests run against a temp directory. Thread-safe.
public final class TrashCandidateStore: @unchecked Sendable {
    private struct State: Codable {
        var candidates: [TrashCandidate] = []
        var keptPaths: Set<String> = []
    }

    private let fileURL: URL
    private let lock = NSLock()
    private var state: State

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(State.self, from: data) {
            state = loaded
        } else {
            state = State()
        }
    }

    public var candidates: [TrashCandidate] {
        lock.lock(); defer { lock.unlock() }
        return state.candidates
    }

    public func isKept(path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return state.keptPaths.contains(path)
    }

    /// Adds a candidate unless its path is kept or already listed.
    /// Returns the stored candidate, or nil when skipped.
    @discardableResult
    public func add(
        path: String, sizeBytes: Int64, lastOpened: Date, now: Date, reviewWindow: TimeInterval
    ) -> TrashCandidate? {
        lock.lock(); defer { lock.unlock() }
        guard !state.keptPaths.contains(path),
              !state.candidates.contains(where: { $0.path == path })
        else { return nil }
        let candidate = TrashCandidate(
            path: path, sizeBytes: sizeBytes, lastOpened: lastOpened,
            addedAt: now, deadline: now.addingTimeInterval(reviewWindow)
        )
        state.candidates.append(candidate)
        save()
        return candidate
    }

    /// "Keep": drops the ids from the list and excludes their paths forever.
    public func keep(ids: Set<UUID>) {
        lock.lock(); defer { lock.unlock() }
        for candidate in state.candidates where ids.contains(candidate.id) {
            state.keptPaths.insert(candidate.path)
        }
        state.candidates.removeAll { ids.contains($0.id) }
        save()
    }

    /// Drops candidates without excluding them (trashed, or evicted because the
    /// file was used/moved). They may re-qualify in a future scan.
    public func remove(ids: Set<UUID>) {
        lock.lock(); defer { lock.unlock() }
        state.candidates.removeAll { ids.contains($0.id) }
        save()
    }

    public func candidate(id: UUID) -> TrashCandidate? {
        lock.lock(); defer { lock.unlock() }
        return state.candidates.first { $0.id == id }
    }

    /// Candidates whose review window has expired as of `now`.
    public func expired(now: Date) -> [TrashCandidate] {
        lock.lock(); defer { lock.unlock() }
        return state.candidates.filter { $0.deadline <= now }
    }

    /// Clears pending candidates (feature disabled). The keep-list survives.
    public func clearCandidates() {
        lock.lock(); defer { lock.unlock() }
        state.candidates.removeAll()
        save()
    }

    private func save() {
        // Callers hold the lock. Best-effort; the list is reconstructible.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
