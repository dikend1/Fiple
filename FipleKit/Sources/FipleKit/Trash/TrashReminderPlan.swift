import Foundation

/// Builds the phone's Smart Trash reminder schedule from a candidate snapshot:
/// one entry 2 days before the nearest deadline, one 1 day before, then every
/// 3 hours through the final day up to the deadline itself.
///
/// The series anchors on the nearest **future** deadline. An already-expired
/// candidate (the Mac was asleep or off at its deadline, so enforcement hasn't
/// run yet) must not anchor the series: every fire date would land in the past
/// and the whole rebuild would silently drop reminders for candidates that are
/// still reviewable. Expired candidates are likewise excluded from the counts —
/// they belong to deadline enforcement, not to future reminders.
///
/// Pure schedule math with `now` injected; the iOS app turns entries into
/// `UNNotificationRequest`s.
public enum TrashReminderPlan {
    public struct Entry: Equatable, Sendable {
        /// Seconds from `now` until the reminder fires. Always > 60.
        public let fireIn: TimeInterval
        public let body: String

        public init(fireIn: TimeInterval, body: String) {
            self.fireIn = fireIn
            self.body = body
        }
    }

    /// Escalation cadence through the final day.
    private static let finalDayInterval: TimeInterval = 3 * 3_600
    /// Entries closer than this are already stale by delivery time — skip them.
    private static let minLead: TimeInterval = 60

    public static func entries(for candidates: [TrashCandidate], now: Date) -> [Entry] {
        let live = candidates.filter { $0.deadline > now }
        guard let nearest = live.map(\.deadline).min() else { return [] }

        let lead = nearest.timeIntervalSince(now)
        let one = live.count == 1
        let files = one ? "1 file" : "\(live.count) files"

        var entries: [Entry] = []
        func add(at offset: TimeInterval, _ body: String) {
            guard offset > minLead else { return }
            entries.append(Entry(fireIn: offset, body: body))
        }

        add(at: lead - 2 * 86_400,
            "\(files) on your Mac \(one ? "moves" : "move") to the Trash in 2 days. Review \(one ? "it" : "them") in Fiple.")
        add(at: lead - 86_400,
            "\(files) \(one ? "moves" : "move") to your Mac's Trash tomorrow. Review \(one ? "it" : "them") in Fiple.")
        // The final day: escalate every 3 hours up to the deadline itself.
        var t = lead - 86_400 + finalDayInterval
        while t <= lead {
            let hoursLeft = max(0, Int((lead - t) / 3_600))
            add(at: t, hoursLeft == 0
                ? "\(files) \(one ? "is" : "are") moving to your Mac's Trash now. \(one ? "It stays" : "They stay") recoverable in the Trash."
                : "\(files) \(one ? "moves" : "move") to your Mac's Trash in \(hoursLeft)h. Review \(one ? "it" : "them") in Fiple.")
            t += finalDayInterval
        }
        return entries
    }
}
