import Foundation
import Testing
@testable import FipleKit

@Suite("Stale file scanner")
struct StaleFileScannerTests {
    private let now = Date()
    private let day: TimeInterval = 86_400

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scanner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeStore() -> TrashCandidateStore {
        TrashCandidateStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("scanner-store-\(UUID().uuidString).json")
        )
    }

    /// Creates a file and backdates its access+modification dates.
    private func writeFile(_ name: String, in dir: URL, usedDaysAgo: Double) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        try setUsed(url, date: now.addingTimeInterval(-usedDaysAgo * day))
        return url
    }

    private func setUsed(_ url: URL, date: Date) throws {
        var url = url
        var values = URLResourceValues()
        values.contentAccessDate = date
        values.contentModificationDate = date
        try url.setResourceValues(values)
    }

    @Test("Stale files become candidates; fresh ones don't")
    func staleDetected() throws {
        let dir = try makeTempDir()
        let stale = try writeFile("old.png", in: dir, usedDaysAgo: 90)
        _ = try writeFile("fresh.png", in: dir, usedDaysAgo: 5)

        let store = makeStore()
        let added = StaleFileScanner().scan(folders: [dir], store: store, now: now)
        #expect(added == 1)
        // Canonicalize both sides: the scanner may report /private/var for /var.
        let found = store.candidates.map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path }
        #expect(found == [stale.resolvingSymlinksInPath().path])
    }

    @Test("A candidate used again leaves the list on the next scan")
    func usedAgainEvicted() throws {
        let dir = try makeTempDir()
        let file = try writeFile("doc.pdf", in: dir, usedDaysAgo: 90)
        let store = makeStore()
        let scanner = StaleFileScanner()
        scanner.scan(folders: [dir], store: store, now: now)
        #expect(store.candidates.count == 1)

        // File is opened after candidacy.
        try setUsed(file, date: now.addingTimeInterval(60))
        scanner.scan(folders: [dir], store: store, now: now.addingTimeInterval(120))
        #expect(store.candidates.isEmpty)
    }

    @Test("A vanished candidate is evicted without action")
    func missingEvicted() throws {
        let dir = try makeTempDir()
        let file = try writeFile("gone.txt", in: dir, usedDaysAgo: 90)
        let store = makeStore()
        let scanner = StaleFileScanner()
        scanner.scan(folders: [dir], store: store, now: now)
        #expect(store.candidates.count == 1)

        try FileManager.default.removeItem(at: file)
        scanner.evictUsedOrMissing(store: store, now: now)
        #expect(store.candidates.isEmpty)
    }

    @Test("Kept files are never re-proposed by scans")
    func keptSkippedByScan() throws {
        let dir = try makeTempDir()
        _ = try writeFile("keepme.png", in: dir, usedDaysAgo: 90)
        let store = makeStore()
        let scanner = StaleFileScanner()
        scanner.scan(folders: [dir], store: store, now: now)
        store.keep(ids: Set(store.candidates.map(\.id)))

        let added = scanner.scan(folders: [dir], store: store, now: now)
        #expect(added == 0)
        #expect(store.candidates.isEmpty)
    }
}
