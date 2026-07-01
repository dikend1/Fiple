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
