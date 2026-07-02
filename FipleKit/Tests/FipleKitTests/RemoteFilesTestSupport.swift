import Foundation
@testable import FipleKit

/// In-memory ``RemoteFileStore`` for tests — stands in for the private CloudKit
/// database so cache logic can be exercised without iCloud.
actor InMemoryRemoteFileStore: RemoteFileStore {
    private var files: [String: RemoteFile] = [:]
    private var payloads: [String: Data] = [:]
    /// Records every deletion so tests can assert eviction targets the cloud
    /// cache (and nothing else).
    private(set) var deletedRecordNames: [String] = []

    func seed(_ file: RemoteFile, payload: Data = Data()) {
        files[file.recordName] = file
        payloads[file.recordName] = payload
    }

    func list() async throws -> [RemoteFile] { Array(files.values) }

    func upload(_ file: RemoteFile, payload: Data, thumbnail: Data?) async throws {
        files[file.recordName] = file
        payloads[file.recordName] = payload
    }

    func download(recordName: String, onProgress: (@Sendable (Double) -> Void)?) async throws -> Data {
        guard let data = payloads[recordName] else {
            throw NSError(domain: "InMemoryRemoteFileStore", code: 404)
        }
        onProgress?(1.0)
        return data
    }

    func delete(recordNames: [String]) async throws {
        for name in recordNames {
            files[name] = nil
            payloads[name] = nil
            deletedRecordNames.append(name)
        }
    }

    func setPinned(recordName: String, _ pinned: Bool) async throws {
        files[recordName]?.isPinned = pinned
    }

    func purgeAll() async throws {
        deletedRecordNames.append(contentsOf: files.keys)
        files.removeAll()
        payloads.removeAll()
    }

    var count: Int { files.count }
    func contains(_ recordName: String) -> Bool { files[recordName] != nil }
    func file(_ recordName: String) -> RemoteFile? { files[recordName] }
}

/// Read-only stub filesystem keyed by path. Has no way to mutate disk — mirroring
/// the real ``FileReading`` contract — and counts reads so tests can prove the
/// deletion path never touches disk.
final class StubFileReader: FileReading, @unchecked Sendable {
    struct Entry: Sendable { var meta: FileMetadata; var data: Data }
    private let entries: [String: Entry]
    private let lock = NSLock()
    private var _reads = 0

    init(_ entries: [String: Entry]) { self.entries = entries }

    var reads: Int { lock.withLock { _reads } }

    func metadata(at url: URL) throws -> FileMetadata {
        guard let entry = entries[url.path] else {
            throw NSError(domain: "StubFileReader", code: 404)
        }
        lock.withLock { _reads += 1 }
        return entry.meta
    }

    func readData(at url: URL) throws -> Data {
        guard let entry = entries[url.path] else {
            throw NSError(domain: "StubFileReader", code: 404)
        }
        lock.withLock { _reads += 1 }
        return entry.data
    }
}

extension RemoteFile {
    /// Terse builder for tests: identity + size/age, defaults for the rest.
    static func fixture(
        name: String,
        folder: SourceFolder = .documents,
        path: String? = nil,
        size: Int64 = 1_000,
        modifiedAt: Date,
        pinned: Bool = false,
        device: String = "mac-1"
    ) -> RemoteFile {
        RemoteFile(
            fileName: name,
            sourceFolder: folder,
            relativePath: path ?? name,
            sizeBytes: size,
            modifiedAt: modifiedAt,
            contentType: "public.data",
            isPinned: pinned,
            sourceDeviceID: device
        )
    }
}
