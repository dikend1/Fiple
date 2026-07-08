import Foundation
import Testing
@testable import FipleKit

@Suite("Trash candidate store")
struct TrashCandidateStoreTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let week: TimeInterval = 7 * 86_400

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("trash-store-\(UUID().uuidString).json")
    }

    @Test("Adding lists a candidate with the review deadline")
    func addSetsDeadline() {
        let store = TrashCandidateStore(fileURL: tempFile())
        let added = store.add(
            path: "/tmp/shot.png", sizeBytes: 42, lastOpened: now.addingTimeInterval(-90 * 86_400),
            now: now, reviewWindow: week
        )
        #expect(added != nil)
        #expect(store.candidates.count == 1)
        #expect(added?.deadline == now.addingTimeInterval(week))
    }

    @Test("Duplicates and kept paths are not re-added")
    func duplicatesAndKeptSkipped() {
        let store = TrashCandidateStore(fileURL: tempFile())
        let first = store.add(path: "/tmp/a", sizeBytes: 1, lastOpened: now, now: now, reviewWindow: week)!
        #expect(store.add(path: "/tmp/a", sizeBytes: 1, lastOpened: now, now: now, reviewWindow: week) == nil)

        store.keep(ids: [first.id])
        #expect(store.candidates.isEmpty)
        #expect(store.isKept(path: "/tmp/a"))
        // Kept forever: never proposed again.
        #expect(store.add(path: "/tmp/a", sizeBytes: 1, lastOpened: now, now: now, reviewWindow: week) == nil)
    }

    @Test("Removed (trashed/evicted) candidates may re-qualify later")
    func removeIsNotKeep() {
        let store = TrashCandidateStore(fileURL: tempFile())
        let c = store.add(path: "/tmp/b", sizeBytes: 1, lastOpened: now, now: now, reviewWindow: week)!
        store.remove(ids: [c.id])
        #expect(store.candidates.isEmpty)
        #expect(!store.isKept(path: "/tmp/b"))
        #expect(store.add(path: "/tmp/b", sizeBytes: 1, lastOpened: now, now: now, reviewWindow: week) != nil)
    }

    @Test("expired(now:) returns only past-deadline candidates")
    func expiredFilters() {
        let store = TrashCandidateStore(fileURL: tempFile())
        let old = store.add(path: "/tmp/old", sizeBytes: 1, lastOpened: now, now: now, reviewWindow: week)!
        store.add(path: "/tmp/new", sizeBytes: 1, lastOpened: now, now: now.addingTimeInterval(6 * 86_400), reviewWindow: week)
        let expired = store.expired(now: now.addingTimeInterval(week))
        #expect(expired.map(\.id) == [old.id])
    }

    @Test("State persists across relaunch; keep-list survives clearCandidates")
    func persistenceRoundTrip() {
        let url = tempFile()
        let store = TrashCandidateStore(fileURL: url)
        let a = store.add(path: "/tmp/a", sizeBytes: 1, lastOpened: now, now: now, reviewWindow: week)!
        store.add(path: "/tmp/b", sizeBytes: 2, lastOpened: now, now: now, reviewWindow: week)
        store.keep(ids: [a.id])

        let reloaded = TrashCandidateStore(fileURL: url)
        #expect(reloaded.candidates.map(\.path) == ["/tmp/b"])
        #expect(reloaded.isKept(path: "/tmp/a"))

        reloaded.clearCandidates()
        let again = TrashCandidateStore(fileURL: url)
        #expect(again.candidates.isEmpty)
        #expect(again.isKept(path: "/tmp/a"))
    }
}
