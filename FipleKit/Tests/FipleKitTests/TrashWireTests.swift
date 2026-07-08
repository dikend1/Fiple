import Foundation
import Testing
@testable import FipleKit

@Suite("Smart Trash wire messages")
struct TrashWireTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("Client trash messages round-trip")
    func clientRoundTrip() throws {
        let id = UUID()
        let messages: [ClientMessage] = [
            .trashThumbnail(candidateID: id),
            .trashAction(ids: [id, UUID()], decision: .trash),
            .trashAction(ids: [id], decision: .keep),
        ]
        for message in messages {
            let data = try MessageCodec.encode(message)
            #expect(try MessageCodec.decode(ClientMessage.self, from: data) == message)
        }
    }

    @Test("Server trash messages round-trip")
    func serverRoundTrip() throws {
        let candidate = TrashCandidate(
            path: "/Users/x/Desktop/shot.png", sizeBytes: 1234,
            lastOpened: now, addedAt: now, deadline: now.addingTimeInterval(604_800)
        )
        let id = UUID()
        let messages: [ServerMessage] = [
            .trashCandidates(candidates: [candidate]),
            .trashThumbnail(candidateID: id, jpeg: Data([0xFF, 0xD8, 0xFF])),
            .trashActionResult(trashed: [id], kept: [], unknown: [UUID()]),
        ]
        for message in messages {
            let data = try MessageCodec.encode(message)
            #expect(try MessageCodec.decode(ServerMessage.self, from: data) == message)
        }
    }

    @Test("An unknown trash decision decodes as the non-destructive keep")
    func unknownDecisionIsKeep() throws {
        let json = #"{"type":"trashAction","ids":["\#(UUID().uuidString)"],"decision":"incinerate"}"#
        let decoded = try MessageCodec.decode(ClientMessage.self, from: Data(json.utf8))
        guard case let .trashAction(_, decision) = decoded else {
            Issue.record("wrong case"); return
        }
        #expect(decision == .keep)
    }
}

#if os(macOS)
@Suite("Trash review handler")
struct TrashReviewHandlerTests {
    private let now = Date()
    private let day: TimeInterval = 86_400

    private func makeFixture() throws -> (dir: URL, store: TrashCandidateStore) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, TrashCandidateStore(fileURL: dir.appendingPathComponent("store.json")))
    }

    private func candidateFile(_ name: String, in dir: URL, store: TrashCandidateStore) throws -> TrashCandidate {
        var url = dir.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        var values = URLResourceValues()
        values.contentAccessDate = now.addingTimeInterval(-90 * day)
        values.contentModificationDate = now.addingTimeInterval(-90 * day)
        try url.setResourceValues(values)
        return store.add(
            path: url.path, sizeBytes: 1, lastOpened: now.addingTimeInterval(-90 * day),
            now: now.addingTimeInterval(-60), reviewWindow: 7 * day
        )!
    }

    @Test("Trash decision moves resolved files and reports unknown ids")
    func trashDecision() throws {
        let (dir, store) = try makeFixture()
        let candidate = try candidateFile("a.png", in: dir, store: store)
        let forged = UUID()

        let result = TrashReviewHandler().apply(
            ids: [candidate.id, forged], decision: .trash,
            store: store, scanner: StaleFileScanner(), now: now
        )
        #expect(result == .trashActionResult(trashed: [candidate.id], kept: [], unknown: [forged]))
        #expect(!FileManager.default.fileExists(atPath: candidate.path))
        #expect(store.candidates.isEmpty)
    }

    @Test("Keep decision excludes without touching the file")
    func keepDecision() throws {
        let (dir, store) = try makeFixture()
        let candidate = try candidateFile("b.pdf", in: dir, store: store)

        let result = TrashReviewHandler().apply(
            ids: [candidate.id], decision: .keep,
            store: store, scanner: StaleFileScanner(), now: now
        )
        #expect(result == .trashActionResult(trashed: [], kept: [candidate.id], unknown: []))
        #expect(FileManager.default.fileExists(atPath: candidate.path))
        #expect(store.isKept(path: candidate.path))
    }

    @Test("A file used after the phone's snapshot is not trashed")
    func staleSnapshotSafe() throws {
        let (dir, store) = try makeFixture()
        let candidate = try candidateFile("c.txt", in: dir, store: store)

        // Used right before the decision arrives.
        var url = URL(fileURLWithPath: candidate.path)
        var values = URLResourceValues()
        values.contentAccessDate = now
        try url.setResourceValues(values)

        let result = TrashReviewHandler().apply(
            ids: [candidate.id], decision: .trash,
            store: store, scanner: StaleFileScanner(), now: now.addingTimeInterval(30)
        )
        #expect(result == .trashActionResult(trashed: [], kept: [], unknown: [candidate.id]))
        #expect(FileManager.default.fileExists(atPath: candidate.path))
    }
}
#endif
