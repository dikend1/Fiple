import Foundation
import CloudKit

/// Real ``RemoteFileStore`` backed by the user's **private** CloudKit database.
///
/// An `actor` so all access to non-`Sendable` CloudKit types (`CKRecord`,
/// `CKAsset`) is serialized and stays local to this instance — the public API
/// only ever crosses the boundary with `Sendable` values (`RemoteFile`, `Data`).
///
/// Requires the iCloud/CloudKit entitlement and the container to exist in the
/// developer account; the record type `RemoteFile` and its queried fields must be
/// marked *queryable* in the CloudKit schema. There is deliberately no operation
/// that touches the Mac's local filesystem — deletion here removes only cloud
/// copies (safety invariant).
public actor CloudKitRemoteFileStore: RemoteFileStore {
    public static let recordType = "RemoteFile"

    private let database: CKDatabase

    /// - Parameter containerIdentifier: e.g. `iCloud.com.maksatov.fipleapp`. When
    ///   nil, the app's default container is used.
    public init(containerIdentifier: String? = nil) {
        let container = containerIdentifier.map { CKContainer(identifier: $0) } ?? .default()
        self.database = container.privateCloudDatabase
    }

    public func list() async throws -> [RemoteFile] {
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        var files: [RemoteFile] = []
        var cursor: CKQueryOperation.Cursor?

        do {
            repeat {
                let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
                if let cursor {
                    page = try await database.records(continuingMatchFrom: cursor)
                } else {
                    page = try await database.records(matching: query)
                }
                for (_, result) in page.matchResults {
                    if case let .success(record) = result, let file = Self.file(from: record) {
                        files.append(file)
                    }
                }
                cursor = page.queryCursor
            } while cursor != nil
        } catch let error as CKError where Self.isEmptySchemaError(error) {
            // The record type doesn't exist yet (nothing uploaded) or the
            // queryable index isn't configured — treat as an empty cache so the
            // first upload can proceed and create the type. Full listing (and
            // eviction) needs the `recordName` QUERYABLE index in the CloudKit
            // schema; until then this degrades gracefully instead of throwing.
            return []
        }

        return files
    }

    /// True for the "record type not found" / "field not queryable" errors that
    /// simply mean the schema isn't set up yet — not a real failure.
    private static func isEmptySchemaError(_ error: CKError) -> Bool {
        switch error.code {
        case .unknownItem, .invalidArguments: return true
        default: return false
        }
    }

    public func upload(_ file: RemoteFile, payload: Data, thumbnail: Data?) async throws {
        let recordID = CKRecord.ID(recordName: file.recordName)
        // Fetch-then-update so an edit overwrites the same record; create if absent.
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        }
        Self.apply(file, to: record)

        let payloadURL = try Self.writeTemp(payload, name: file.recordName + ".payload")
        defer { try? FileManager.default.removeItem(at: payloadURL) }
        record["payload"] = CKAsset(fileURL: payloadURL)

        var thumbURL: URL?
        if let thumbnail {
            let url = try Self.writeTemp(thumbnail, name: file.recordName + ".thumb")
            thumbURL = url
            record["thumbnail"] = CKAsset(fileURL: url)
        }
        defer { if let thumbURL { try? FileManager.default.removeItem(at: thumbURL) } }

        _ = try await database.save(record)
    }

    public func download(recordName: String) async throws -> Data {
        let record = try await database.record(for: CKRecord.ID(recordName: recordName))
        guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL else {
            throw CKError(.assetFileNotFound)
        }
        return try Data(contentsOf: url)
    }

    public func delete(recordNames: [String]) async throws {
        for name in recordNames {
            _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: name))
        }
    }

    public func setPinned(recordName: String, _ pinned: Bool) async throws {
        let record = try await database.record(for: CKRecord.ID(recordName: recordName))
        record["isPinned"] = pinned ? 1 : 0
        _ = try await database.save(record)
    }

    public func purgeAll() async throws {
        let all = try await list()
        try await delete(recordNames: all.map(\.recordName))
    }

    // MARK: - Mapping

    private static func apply(_ file: RemoteFile, to record: CKRecord) {
        record["fileName"] = file.fileName
        record["sourceFolder"] = file.sourceFolder.rawValue
        record["relativePath"] = file.relativePath
        record["sizeBytes"] = file.sizeBytes
        record["modifiedAt"] = file.modifiedAt
        record["contentType"] = file.contentType
        record["isPinned"] = file.isPinned ? 1 : 0
        record["sourceDeviceID"] = file.sourceDeviceID
    }

    private static func file(from record: CKRecord) -> RemoteFile? {
        guard
            let fileName = record["fileName"] as? String,
            let folderRaw = record["sourceFolder"] as? String,
            let folder = SourceFolder(rawValue: folderRaw),
            let relativePath = record["relativePath"] as? String,
            let size = record["sizeBytes"] as? Int64,
            let modifiedAt = record["modifiedAt"] as? Date,
            let contentType = record["contentType"] as? String,
            let deviceID = record["sourceDeviceID"] as? String
        else { return nil }
        let pinned = (record["isPinned"] as? Int64 ?? 0) != 0
        return RemoteFile(
            recordName: record.recordID.recordName,
            fileName: fileName,
            sourceFolder: folder,
            relativePath: relativePath,
            sizeBytes: size,
            modifiedAt: modifiedAt,
            contentType: contentType,
            isPinned: pinned,
            sourceDeviceID: deviceID
        )
    }

    private static func writeTemp(_ data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
