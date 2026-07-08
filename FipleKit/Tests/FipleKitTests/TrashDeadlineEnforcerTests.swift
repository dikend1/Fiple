#if os(macOS)
import Foundation
import Testing
@testable import FipleKit

@Suite("Trash deadline enforcement")
struct TrashDeadlineEnforcerTests {
    private let now = Date()
    private let day: TimeInterval = 86_400

    private func makeDirAndStore() throws -> (URL, TrashCandidateStore) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("enforcer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = TrashCandidateStore(fileURL: dir.appendingPathComponent("store.json"))
        return (dir, store)
    }

    private func backdatedFile(_ name: String, in dir: URL, daysAgo: Double) throws -> URL {
        var url = dir.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        var values = URLResourceValues()
        values.contentAccessDate = now.addingTimeInterval(-daysAgo * day)
        values.contentModificationDate = now.addingTimeInterval(-daysAgo * day)
        try url.setResourceValues(values)
        return url
    }

    @Test("Expired candidate moves to the system Trash; unexpired stays put")
    func expiredIsTrashed() throws {
        let (dir, store) = try makeDirAndStore()
        let old = try backdatedFile("old.png", in: dir, daysAgo: 90)
        let fresh = try backdatedFile("pending.png", in: dir, daysAgo: 90)

        // "old" got its deadline a week ago; "pending" still has time.
        store.add(path: old.path, sizeBytes: 1, lastOpened: now.addingTimeInterval(-90 * day),
                  now: now.addingTimeInterval(-8 * day), reviewWindow: 7 * day)
        store.add(path: fresh.path, sizeBytes: 1, lastOpened: now.addingTimeInterval(-90 * day),
                  now: now, reviewWindow: 7 * day)

        let trashed = TrashDeadlineEnforcer().enforce(
            store: store, scanner: StaleFileScanner(), now: now
        )
        #expect(trashed.map(\.path) == [old.path])
        #expect(!FileManager.default.fileExists(atPath: old.path)) // moved away
        #expect(FileManager.default.fileExists(atPath: fresh.path)) // untouched
        #expect(store.candidates.map(\.path) == [fresh.path])
    }

    @Test("A file used after candidacy is evicted, never trashed")
    func usedFileEscapesEnforcement() throws {
        let (dir, store) = try makeDirAndStore()
        var file = try backdatedFile("doc.pdf", in: dir, daysAgo: 90)
        store.add(path: file.path, sizeBytes: 1, lastOpened: now.addingTimeInterval(-90 * day),
                  now: now.addingTimeInterval(-8 * day), reviewWindow: 7 * day)

        // Opened at the last minute — after candidacy.
        var values = URLResourceValues()
        values.contentAccessDate = now
        try file.setResourceValues(values)

        let trashed = TrashDeadlineEnforcer().enforce(
            store: store, scanner: StaleFileScanner(), now: now
        )
        #expect(trashed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path)) // still there
        #expect(store.candidates.isEmpty) // evicted, not pending
    }

    @Test("A vanished expired candidate is dropped without error")
    func missingExpiredDropped() throws {
        let (dir, store) = try makeDirAndStore()
        let file = try backdatedFile("gone.txt", in: dir, daysAgo: 90)
        store.add(path: file.path, sizeBytes: 1, lastOpened: now.addingTimeInterval(-90 * day),
                  now: now.addingTimeInterval(-8 * day), reviewWindow: 7 * day)
        try FileManager.default.removeItem(at: file)

        let trashed = TrashDeadlineEnforcer().enforce(
            store: store, scanner: StaleFileScanner(), now: now
        )
        #expect(trashed.isEmpty)
        #expect(store.candidates.isEmpty)
    }
}
#endif
