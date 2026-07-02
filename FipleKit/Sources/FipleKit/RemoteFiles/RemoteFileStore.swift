import Foundation

/// Abstraction over the private CloudKit database for cached files.
///
/// FipleKit depends only on this protocol, so all cache logic is testable with
/// an in-memory fake and the real CloudKit adapter lives in the app targets
/// (where the iCloud entitlement is provisioned). By construction the store has
/// **no** operation that touches the Mac's local filesystem — only cloud copies
/// — which is one half of the read-only safety invariant.
public protocol RemoteFileStore: Sendable {
    /// All file descriptors currently in the cache (both pools).
    func list() async throws -> [RemoteFile]

    /// Upload or update a file: its descriptor plus the payload bytes and an
    /// optional thumbnail. Overwrites the record with the same `recordName`.
    func upload(_ file: RemoteFile, payload: Data, thumbnail: Data?) async throws

    /// Fetch the payload bytes for a cached file (the phone's download path),
    /// reporting fetch progress (0…1) if a handler is given.
    func download(recordName: String, onProgress: (@Sendable (Double) -> Void)?) async throws -> Data

    /// Remove cache copies by `recordName`. This is the *only* deletion in the
    /// system and it targets the cloud cache exclusively — never disk originals.
    func delete(recordNames: [String]) async throws

    /// Flip the pinned flag on a cached record.
    func setPinned(recordName: String, _ pinned: Bool) async throws

    /// Remove every cached copy (used when the feature is turned off on the Mac).
    func purgeAll() async throws
}

public extension RemoteFileStore {
    /// Convenience: download without progress reporting.
    func download(recordName: String) async throws -> Data {
        try await download(recordName: recordName, onProgress: nil)
    }
}
