import Foundation
import Testing
@testable import FipleKit

@Suite("RemoteFile identity")
struct RemoteFileTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    @Test("recordName is stable across size/date changes (an edit updates, not duplicates)")
    func recordNameStableAcrossEdits() {
        let v1 = RemoteFile.fixture(name: "Q3.key", path: "Decks/Q3.key", size: 10, modifiedAt: t0)
        let v2 = RemoteFile.fixture(
            name: "Q3.key", path: "Decks/Q3.key", size: 9_999,
            modifiedAt: t0.addingTimeInterval(5_000)
        )
        #expect(v1.recordName == v2.recordName)
    }

    @Test("recordName differs by folder, path, and device")
    func recordNameDiffersByIdentity() {
        let base = RemoteFile.recordName(deviceID: "mac-1", folder: .documents, relativePath: "a.txt")
        #expect(base != RemoteFile.recordName(deviceID: "mac-1", folder: .desktop, relativePath: "a.txt"))
        #expect(base != RemoteFile.recordName(deviceID: "mac-1", folder: .documents, relativePath: "b.txt"))
        #expect(base != RemoteFile.recordName(deviceID: "mac-2", folder: .documents, relativePath: "a.txt"))
    }

    @Test("recordName is deterministic (same inputs → same hash)")
    func recordNameDeterministic() {
        let a = RemoteFile.recordName(deviceID: "mac-1", folder: .downloads, relativePath: "x/y.pdf")
        let b = RemoteFile.recordName(deviceID: "mac-1", folder: .downloads, relativePath: "x/y.pdf")
        #expect(a == b)
        #expect(a.count == 64) // SHA-256 hex
    }

    @Test("RemoteFile round-trips through Codable")
    func codableRoundTrip() throws {
        let file = RemoteFile.fixture(name: "notes.md", modifiedAt: t0, pinned: true)
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(RemoteFile.self, from: data)
        #expect(decoded == file)
    }
}
