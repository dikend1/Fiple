import Foundation
import CryptoKit

/// One of the three standard folders the Mac mirrors for off-LAN access.
///
/// Coverage is deliberately limited to these (see PRD `fiple-remote-file-access`)
/// so the cache — and the blast radius if the Apple ID is compromised — stays
/// bounded to a user's working files rather than the whole home directory.
public enum SourceFolder: String, Sendable, Codable, CaseIterable, Equatable {
    case desktop
    case documents
    case downloads
}

/// Metadata describing one cached file in the private CloudKit database.
///
/// This is *only* the descriptor — the heavy bytes (the file itself and its
/// thumbnail) travel as CloudKit assets handled by ``RemoteFileStore``, never
/// inside this value, so listing the phone's Files screen stays cheap.
///
/// The ``recordName`` is a *stable* identity derived from device + folder +
/// path, so re-uploading a changed file overwrites its record instead of
/// creating a duplicate (see ``recordName(deviceID:folder:relativePath:)``).
public struct RemoteFile: Identifiable, Sendable, Equatable, Codable {
    /// Stable CloudKit record name — see ``recordName(deviceID:folder:relativePath:)``.
    public let recordName: String
    public var fileName: String
    public var sourceFolder: SourceFolder
    /// Path within `sourceFolder`, e.g. `Decks/Q3.key`. Empty for a file sitting
    /// directly in the folder.
    public var relativePath: String
    public var sizeBytes: Int64
    /// Last-modified time on the Mac. Drives newest-first sorting and
    /// oldest-first eviction.
    public var modifiedAt: Date
    /// Uniform Type Identifier, e.g. `com.apple.keynote.key`, for icon/preview.
    public var contentType: String
    /// Favorited → exempt from fresh-pool eviction, tracked against the separate
    /// pinned budget.
    public var isPinned: Bool
    /// Which Mac produced this record (future multi-Mac; single-Mac in v1 UX).
    public let sourceDeviceID: String

    public var id: String { recordName }

    public init(
        recordName: String,
        fileName: String,
        sourceFolder: SourceFolder,
        relativePath: String,
        sizeBytes: Int64,
        modifiedAt: Date,
        contentType: String,
        isPinned: Bool = false,
        sourceDeviceID: String
    ) {
        self.recordName = recordName
        self.fileName = fileName
        self.sourceFolder = sourceFolder
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.contentType = contentType
        self.isPinned = isPinned
        self.sourceDeviceID = sourceDeviceID
    }

    /// Convenience initializer that computes the stable ``recordName`` from
    /// identity fields, so callers can't accidentally desync the two.
    public init(
        fileName: String,
        sourceFolder: SourceFolder,
        relativePath: String,
        sizeBytes: Int64,
        modifiedAt: Date,
        contentType: String,
        isPinned: Bool = false,
        sourceDeviceID: String
    ) {
        self.init(
            recordName: Self.recordName(
                deviceID: sourceDeviceID,
                folder: sourceFolder,
                relativePath: relativePath
            ),
            fileName: fileName,
            sourceFolder: sourceFolder,
            relativePath: relativePath,
            sizeBytes: sizeBytes,
            modifiedAt: modifiedAt,
            contentType: contentType,
            isPinned: isPinned,
            sourceDeviceID: sourceDeviceID
        )
    }

    /// Stable identity for a file: a hash of `device + folder + relativePath`.
    ///
    /// Deliberately excludes `size`/`modifiedAt` so editing a file keeps the same
    /// record (an update, not a duplicate). Deterministic across launches and
    /// platforms (SHA-256 over a NUL-separated string), so the Mac and phone
    /// agree on identity without coordination.
    public static func recordName(
        deviceID: String,
        folder: SourceFolder,
        relativePath: String
    ) -> String {
        let key = "\(deviceID)\u{0}\(folder.rawValue)\u{0}\(relativePath)"
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
