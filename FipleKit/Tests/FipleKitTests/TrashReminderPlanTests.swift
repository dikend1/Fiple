import Foundation
import Testing
@testable import FipleKit

@Suite("Trash reminder plan")
struct TrashReminderPlanTests {
    private let now = Date()
    private let day: TimeInterval = 86_400
    private let hour: TimeInterval = 3_600

    private func candidate(_ name: String, deadlineIn interval: TimeInterval) -> TrashCandidate {
        TrashCandidate(
            path: "/tmp/\(name)", sizeBytes: 1,
            lastOpened: now.addingTimeInterval(-30 * day),
            addedAt: now.addingTimeInterval(-7 * day),
            deadline: now.addingTimeInterval(interval)
        )
    }

    @Test("an expired candidate does not collapse the series for live ones")
    func expiredCandidateDoesNotCollapseSeries() {
        // The Mac slept through one candidate's deadline (not yet enforced);
        // three others are still 3 days out. The series must be built from the
        // nearest *future* deadline — before the fix, min() picked the expired
        // one and every reminder was silently dropped.
        let candidates = [
            candidate("expired", deadlineIn: -hour),
            candidate("a", deadlineIn: 3 * day),
            candidate("b", deadlineIn: 3 * day),
            candidate("c", deadlineIn: 3 * day),
        ]
        let entries = TrashReminderPlan.entries(for: candidates, now: now)

        #expect(!entries.isEmpty)
        // 2-days-before, 1-day-before, then 8 three-hourly steps through the
        // final day up to the deadline itself.
        #expect(entries.count == 10)
        // Bodies count only candidates that can still be reviewed, not the
        // expired one already owned by deadline enforcement on the Mac.
        #expect(entries[0].body.hasPrefix("3 files"))
        #expect(entries[0].fireIn > 60)
    }

    @Test("all candidates expired yields no reminders")
    func allExpiredYieldsNothing() {
        let candidates = [
            candidate("x", deadlineIn: -hour),
            candidate("y", deadlineIn: -2 * day),
        ]
        #expect(TrashReminderPlan.entries(for: candidates, now: now).isEmpty)
    }

    @Test("no candidates yields no reminders")
    func emptyInputYieldsNothing() {
        #expect(TrashReminderPlan.entries(for: [], now: now).isEmpty)
    }

    @Test("a 7-day deadline builds the full escalation ending at the deadline")
    func fullSeriesShape() {
        let entries = TrashReminderPlan.entries(
            for: [candidate("solo", deadlineIn: 7 * day)], now: now
        )
        #expect(entries.count == 10)
        #expect(entries[0].fireIn == 5 * day)          // 2 days before
        #expect(entries[1].fireIn == 6 * day)          // 1 day before
        #expect(entries.last?.fireIn == 7 * day)       // the deadline itself
        #expect(entries[0].body == "1 file on your Mac moves to the Trash in 2 days. Review it in Fiple.")
        #expect(entries.last?.body.contains("moving to your Mac's Trash now") == true)
        // Escalation entries stay ordered and 3h apart through the final day.
        for pair in zip(entries.dropFirst(2), entries.dropFirst(3)) {
            #expect(pair.1.fireIn - pair.0.fireIn == 3 * hour)
        }
    }

    @Test("a deadline minutes away yields only the final reminder")
    func imminentDeadlineYieldsFinalReminderOnly() {
        let entries = TrashReminderPlan.entries(
            for: [candidate("soon", deadlineIn: 5 * 60)], now: now
        )
        #expect(entries.count == 1)
        #expect(entries[0].body == "1 file is moving to your Mac's Trash now. It stays recoverable in the Trash.")
    }
}
