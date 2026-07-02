import Foundation
import Testing
@testable import FipleKit

@Suite("RemoteFileCache — orchestration & loopback")
struct RemoteFileCacheTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let mb: Int64 = 1024 * 1024

    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/Users/me/Documents/\(name)") }

    @Test("loopback: a changed file is uploaded and can be downloaded")
    func loopbackUploadDownload() async throws {
        let store = InMemoryRemoteFileStore()
        let reader = StubFileReader([
            url("a.txt").path: .init(
                meta: FileMetadata(sizeBytes: mb, modifiedAt: t0, contentType: "public.plain-text"),
                data: Data("hello".utf8)
            )
        ])
        let cache = RemoteFileCache(store: store, reader: reader, deviceID: "mac-1")

        let outcome = try await cache.handleChange(at: url("a.txt"), folder: .documents, relativePath: "a.txt", now: t0)
        #expect(outcome == .cached(evicted: []))

        let listed = try await store.list()
        #expect(listed.count == 1)
        let recordName = try #require(listed.first?.recordName)
        let data = try await store.download(recordName: recordName)
        #expect(String(decoding: data, as: UTF8.self) == "hello")
    }

    @Test("excluded files are never read or uploaded")
    func excludedFilesSkipped() async throws {
        let store = InMemoryRemoteFileStore()
        let reader = StubFileReader([:]) // no entries; reading would throw
        let cache = RemoteFileCache(store: store, reader: reader, deviceID: "mac-1")

        let outcome = try await cache.handleChange(at: url(".DS_Store"), folder: .documents, relativePath: ".DS_Store", now: t0)
        #expect(outcome == .excluded)
        #expect(reader.reads == 0)          // never touched disk
        await #expect(store.count == 0)     // nothing uploaded
    }

    @Test("oversized files are reported skipped, not uploaded")
    func oversizedSkipped() async throws {
        let store = InMemoryRemoteFileStore()
        let reader = StubFileReader([
            url("big.mov").path: .init(
                meta: FileMetadata(sizeBytes: 500 * mb, modifiedAt: t0, contentType: "public.movie"),
                data: Data()
            )
        ])
        let cache = RemoteFileCache(store: store, reader: reader, deviceID: "mac-1")
        let outcome = try await cache.handleChange(at: url("big.mov"), folder: .documents, relativePath: "big.mov", now: t0)
        #expect(outcome == .skipped(.tooLarge))
        await #expect(store.count == 0)
    }

    @Test("batch reconcile with a shared snapshot lists the store once")
    func sharedSnapshotListsOnce() async throws {
        let store = InMemoryRemoteFileStore()
        let names = ["a.txt", "b.txt", "c.txt"]
        var entries: [String: StubFileReader.Entry] = [:]
        for name in names {
            entries[url(name).path] = .init(
                meta: FileMetadata(sizeBytes: mb, modifiedAt: t0, contentType: "public.plain-text"),
                data: Data(name.utf8)
            )
        }
        let cache = RemoteFileCache(store: store, reader: StubFileReader(entries), deviceID: "mac-1")

        var snapshot = try await store.list()
        for name in names {
            let outcome = try await cache.handleChange(
                at: url(name), folder: .documents, relativePath: name, snapshot: &snapshot, now: t0
            )
            #expect(outcome == .cached(evicted: []))
        }

        await #expect(store.listCalls == 1) // one listing for the whole batch
        await #expect(store.count == 3)
    }

    @Test("a shared snapshot stays coherent: the eviction budget holds across the batch")
    func sharedSnapshotEvictionCoherent() async throws {
        let store = InMemoryRemoteFileStore()
        let planner = CachePlanner(
            freshBudget: CacheBudget(maxAge: 30 * 24 * 60 * 60, maxCount: 2, maxTotalBytes: 100 * mb, maxFileBytes: 50 * mb),
            pinnedBudget: .pinnedDefault
        )
        // a is oldest, c newest — caching all three against a count budget of 2
        // must evict exactly a, which only works if each call sees the uploads
        // the previous ones mirrored into the snapshot.
        let batch: [(String, Date)] = [
            ("a.txt", t0.addingTimeInterval(-20)),
            ("b.txt", t0.addingTimeInterval(-10)),
            ("c.txt", t0),
        ]
        var entries: [String: StubFileReader.Entry] = [:]
        for (name, mtime) in batch {
            entries[url(name).path] = .init(
                meta: FileMetadata(sizeBytes: mb, modifiedAt: mtime, contentType: "public.plain-text"),
                data: Data(name.utf8)
            )
        }
        let cache = RemoteFileCache(store: store, reader: StubFileReader(entries), planner: planner, deviceID: "mac-1")

        var snapshot = try await store.list()
        for (name, _) in batch {
            try await cache.handleChange(
                at: url(name), folder: .documents, relativePath: name, snapshot: &snapshot, now: t0
            )
        }

        await #expect(store.count == 2)
        let oldest = RemoteFile.recordName(deviceID: "mac-1", folder: .documents, relativePath: "a.txt")
        await #expect(store.contains(oldest) == false)
        await #expect(store.listCalls == 1)
    }

    @Test("an unchanged file (same size and mtime) is not re-uploaded")
    func unchangedSkipsUpload() async throws {
        let store = InMemoryRemoteFileStore()
        await store.seed(
            .fixture(name: "a.txt", path: "a.txt", size: mb, modifiedAt: t0),
            payload: Data("v1".utf8)
        )
        let reader = StubFileReader([
            url("a.txt").path: .init(
                meta: FileMetadata(sizeBytes: mb, modifiedAt: t0, contentType: "public.data"),
                data: Data("v1".utf8)
            )
        ])
        let cache = RemoteFileCache(store: store, reader: reader, deviceID: "mac-1")

        let outcome = try await cache.handleChange(at: url("a.txt"), folder: .documents, relativePath: "a.txt", now: t0)
        #expect(outcome == .unchanged)
        let uploads = await store.uploadedRecordNames
        #expect(uploads.isEmpty) // the payload never left the Mac again
    }

    @Test("a modified file (new mtime) is re-uploaded in place")
    func modifiedFileReuploaded() async throws {
        let store = InMemoryRemoteFileStore()
        let old = RemoteFile.fixture(name: "a.txt", path: "a.txt", size: mb, modifiedAt: t0.addingTimeInterval(-60))
        await store.seed(old, payload: Data("v1".utf8))
        let reader = StubFileReader([
            url("a.txt").path: .init(
                meta: FileMetadata(sizeBytes: mb, modifiedAt: t0, contentType: "public.data"),
                data: Data("v2".utf8)
            )
        ])
        let cache = RemoteFileCache(store: store, reader: reader, deviceID: "mac-1")

        let outcome = try await cache.handleChange(at: url("a.txt"), folder: .documents, relativePath: "a.txt", now: t0)
        #expect(outcome == .cached(evicted: []))
        let uploads = await store.uploadedRecordNames
        #expect(uploads == [old.recordName])
        let data = try await store.download(recordName: old.recordName)
        #expect(String(decoding: data, as: UTF8.self) == "v2")
    }

    @Test("an unchanged pinned file is not re-uploaded and stays pinned")
    func unchangedPinnedSkipsUpload() async throws {
        let store = InMemoryRemoteFileStore()
        let pinned = RemoteFile.fixture(name: "keep", path: "keep", size: mb, modifiedAt: t0, pinned: true)
        await store.seed(pinned, payload: Data("v1".utf8))
        let reader = StubFileReader([
            url("keep").path: .init(
                meta: FileMetadata(sizeBytes: mb, modifiedAt: t0, contentType: "public.data"),
                data: Data("v1".utf8)
            )
        ])
        let cache = RemoteFileCache(store: store, reader: reader, deviceID: "mac-1")

        let outcome = try await cache.handleChange(at: url("keep"), folder: .documents, relativePath: "keep", now: t0)
        #expect(outcome == .unchanged)
        let uploads = await store.uploadedRecordNames
        #expect(uploads.isEmpty)
        let still = await store.file(pinned.recordName)
        #expect(still?.isPinned == true)
    }

    @Test("deletion removes only the cloud copy and never reads disk")
    func deletionTargetsCloudOnly() async throws {
        let store = InMemoryRemoteFileStore()
        let seeded = RemoteFile.fixture(name: "gone.txt", path: "gone.txt", modifiedAt: t0)
        await store.seed(seeded)
        let reader = StubFileReader([:])
        let cache = RemoteFileCache(store: store, reader: reader, deviceID: "mac-1")

        try await cache.handleDeletion(folder: .documents, relativePath: "gone.txt")

        await #expect(store.count == 0)
        let deleted = await store.deletedRecordNames
        #expect(deleted == [seeded.recordName]) // eviction hit the cloud cache
        #expect(reader.reads == 0)              // and never the disk
    }

    @Test("disableAndPurge clears the whole cache")
    func purgeClearsCache() async throws {
        let store = InMemoryRemoteFileStore()
        await store.seed(.fixture(name: "a", path: "a", modifiedAt: t0))
        await store.seed(.fixture(name: "b", path: "b", modifiedAt: t0))
        let cache = RemoteFileCache(store: store, reader: StubFileReader([:]), deviceID: "mac-1")

        try await cache.disableAndPurge()
        await #expect(store.count == 0)
    }

    @Test("pin succeeds within budget and is refused past the favorites limit")
    func pinRespectsBudget() async throws {
        let store = InMemoryRemoteFileStore()
        let a = RemoteFile.fixture(name: "a", path: "a", size: mb, modifiedAt: t0)
        let b = RemoteFile.fixture(name: "b", path: "b", size: mb, modifiedAt: t0)
        await store.seed(a); await store.seed(b)

        let planner = CachePlanner(
            freshBudget: .freshDefault,
            pinnedBudget: CacheBudget(maxAge: .greatestFiniteMagnitude, maxCount: 1, maxTotalBytes: 10 * mb, maxFileBytes: 10 * mb)
        )
        let cache = RemoteFileCache(store: store, reader: StubFileReader([:]), planner: planner, deviceID: "mac-1")

        let first = try await cache.pin(recordName: a.recordName)
        #expect(first) // fits: 1 of 1
        let pinnedA = await store.file(a.recordName)
        #expect(pinnedA?.isPinned == true)

        let second = try await cache.pin(recordName: b.recordName)
        #expect(second == false) // over the count budget
        let pinnedB = await store.file(b.recordName)
        #expect(pinnedB?.isPinned == false)
    }

    @Test("a pinned file re-uploads in place, never evicting")
    func pinnedReuploadBypassesEviction() async throws {
        let store = InMemoryRemoteFileStore()
        // One pinned file already cached; fresh budget of 1 would normally evict.
        let pinned = RemoteFile.fixture(name: "keep", path: "keep", size: mb, modifiedAt: t0.addingTimeInterval(-100), pinned: true)
        await store.seed(pinned)
        let reader = StubFileReader([
            url("keep").path: .init(
                meta: FileMetadata(sizeBytes: mb, modifiedAt: t0, contentType: "public.data"),
                data: Data("v2".utf8)
            )
        ])
        let planner = CachePlanner(
            freshBudget: CacheBudget(maxAge: 30 * 24 * 60 * 60, maxCount: 1, maxTotalBytes: 100 * mb, maxFileBytes: 50 * mb),
            pinnedBudget: .pinnedDefault
        )
        let cache = RemoteFileCache(store: store, reader: reader, planner: planner, deviceID: "mac-1")

        let outcome = try await cache.handleChange(at: url("keep"), folder: .documents, relativePath: "keep", now: t0)
        #expect(outcome == .cached(evicted: []))
        let stillPinned = await store.file(pinned.recordName)
        #expect(stillPinned?.isPinned == true) // stayed pinned
        let data = try await store.download(recordName: pinned.recordName)
        #expect(String(decoding: data, as: UTF8.self) == "v2") // content refreshed
    }
}
