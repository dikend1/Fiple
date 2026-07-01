import Foundation

/// Lightweight metadata read from a file on disk, without opening its contents.
public struct FileMetadata: Sendable, Equatable {
    public var sizeBytes: Int64
    public var modifiedAt: Date
    /// Uniform Type Identifier, or a best-effort fallback derived from the
    /// extension.
    public var contentType: String

    public init(sizeBytes: Int64, modifiedAt: Date, contentType: String) {
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.contentType = contentType
    }
}

/// Read-only access to the Mac filesystem.
///
/// This protocol is the *other* half of the safety invariant: it exposes only
/// reads (`metadata`, `readData`) and has **no** delete/move/write operation.
/// The Mac agent depends solely on this type to touch disk, so there is no code
/// path — eviction, feature-disable, or error — that can mutate an original
/// file. Deletion exists only on ``RemoteFileStore`` (the cloud cache).
public protocol FileReading: Sendable {
    /// Size / modified-date / type for a file, without reading its bytes.
    func metadata(at url: URL) throws -> FileMetadata

    /// The full bytes of a file, for upload to the cache.
    func readData(at url: URL) throws -> Data
}
