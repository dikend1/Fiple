import Foundation
import Testing
@testable import FipleKit

@Suite("Trash review session")
struct TrashReviewSessionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func candidate(_ name: String) -> TrashCandidate {
        TrashCandidate(
            path: "/tmp/\(name)", sizeBytes: 1, lastOpened: now.addingTimeInterval(-90 * 86_400),
            addedAt: now, deadline: now.addingTimeInterval(7 * 86_400)
        )
    }

    @Test("Swiping moves the current card and advances the deck")
    func swipeAdvances() {
        let a = candidate("a"), b = candidate("b")
        var session = TrashReviewSession(candidates: [a, b])
        #expect(session.current == a)
        session.swipe(.trash)
        #expect(session.current == b)
        #expect(session.staged == [a])
        #expect(session.reviewed == 1)
        #expect(session.total == 2)
        session.swipe(.keep)
        #expect(session.current == nil)
        #expect(session.keptCount == 1)
        #expect(session.reviewed == 2)
    }

    @Test("Undo steps back through both directions, oldest state restored")
    func undoIsMultiStep() {
        let a = candidate("a"), b = candidate("b")
        var session = TrashReviewSession(candidates: [a, b])
        session.swipe(.trash)   // a → basket
        session.swipe(.keep)    // b → kept
        let firstUndo = session.undo()
        #expect(firstUndo)
        #expect(session.current == b)
        #expect(session.keptCount == 0)
        let secondUndo = session.undo()
        #expect(secondUndo)
        #expect(session.current == a)
        #expect(session.staged.isEmpty)
        let thirdUndo = session.undo()
        #expect(!thirdUndo) // nothing left
    }

    @Test("A basket item can be returned to the deck")
    func returnToDeck() {
        let a = candidate("a"), b = candidate("b")
        var session = TrashReviewSession(candidates: [a, b])
        session.swipe(.trash) // a staged
        session.returnToDeck(id: a.id)
        #expect(session.staged.isEmpty)
        #expect(session.current == a) // back on top for a re-decision
        #expect(session.reviewed == 0)
        #expect(!session.canUndo) // its history entry is gone too
    }

    @Test("Committing empties the basket but keeps progress counted")
    func commitCounts() {
        let a = candidate("a"), b = candidate("b"), c = candidate("c")
        var session = TrashReviewSession(candidates: [a, b, c])
        session.swipe(.trash)
        session.swipe(.keep)
        let trashIDs = session.takeTrashIDs()
        let keepIDs = session.takeKeepIDs()
        #expect(trashIDs == [a.id])
        #expect(keepIDs == [b.id])
        #expect(session.staged.isEmpty)
        #expect(session.reviewed == 2)  // committed decisions still count
        #expect(session.total == 3)
        let undone = session.undo()
        #expect(!undone)                // committed decisions can't be undone
        #expect(session.current == c)
    }

    @Test("Reconcile drops vanished candidates and appends new ones")
    func reconcileSyncsWithSnapshot() {
        let a = candidate("a"), b = candidate("b"), c = candidate("c"), d = candidate("d")
        var session = TrashReviewSession(candidates: [a, b, c])
        session.swipe(.trash) // a staged
        // Mac evicted b (file was used) and found d.
        session.reconcile(with: [a, c, d])
        #expect(session.current == c)
        #expect(session.staged == [a])
        #expect(session.upcoming == [d])
        #expect(session.total == 3)
        // a vanishing (e.g. trashed by deadline) also clears it from the basket
        session.reconcile(with: [c, d])
        #expect(session.staged.isEmpty)
        #expect(!session.canUndo)
    }
}
