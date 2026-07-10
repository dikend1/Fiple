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
        let added = mtimeScanner().scan(folders: [dir], store: store, now: now)
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
        let scanner = mtimeScanner()
        scanner.scan(folders: [dir], store: store, now: now)
        #expect(store.candidates.count == 1)

        // File is opened after candidacy.
        try setUsed(file, date: now.addingTimeInterval(60))
        scanner.scan(folders: [dir], store: store, now: now.addingTimeInterval(120))
        #expect(store.candidates.isEmpty)
    }

    @Test("Raising the threshold immediately evicts candidates that no longer qualify")
    func raisedThresholdEvicts() throws {
        let dir = try makeTempDir()
        // Unused for 20 days: stale at 15, NOT stale at 90.
        _ = try writeFile("meh.zip", in: dir, usedDaysAgo: 20)
        let store = makeStore()

        mtimeScanner(stalenessThreshold: 15 * day).scan(folders: [dir], store: store, now: now)
        #expect(store.candidates.count == 1)

        // The user switches 15 → 90 days; the rescan must clear the list, not
        // leave the old policy's candidates marching toward their deadline.
        mtimeScanner(stalenessThreshold: 90 * day).scan(folders: [dir], store: store, now: now)
        #expect(store.candidates.isEmpty)

        // Switching back finds it again (fresh review window).
        mtimeScanner(stalenessThreshold: 15 * day).scan(folders: [dir], store: store, now: now)
        #expect(store.candidates.count == 1)
    }

    @Test("Finder-truth signal: a freshly added file with an ancient mtime is not stale")
    func finderSignalProtectsFreshFiles() throws {
        let dir = try makeTempDir()
        // An unzipped/downloaded archive often carries an upstream modification
        // date years in the past — but it landed in this folder TODAY. The
        // default (non-injected) signal must weigh the added-to-folder date and
        // refuse to call it stale.
        _ = try writeFile("archive.zip", in: dir, usedDaysAgo: 400)
        let store = makeStore()

        let added = StaleFileScanner().scan(folders: [dir], store: store, now: now)
        #expect(added == 0)
        #expect(store.candidates.isEmpty)
    }

    @Test("A vanished candidate is evicted without action")
    func missingEvicted() throws {
        let dir = try makeTempDir()
        let file = try writeFile("gone.txt", in: dir, usedDaysAgo: 90)
        let store = makeStore()
        let scanner = mtimeScanner()
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
        let scanner = mtimeScanner()
        scanner.scan(folders: [dir], store: store, now: now)
        store.keep(ids: Set(store.candidates.map(\.id)))

        let added = scanner.scan(folders: [dir], store: store, now: now)
        #expect(added == 0)
        #expect(store.candidates.isEmpty)
    }
}
