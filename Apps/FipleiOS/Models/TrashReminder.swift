import FipleKit
import Foundation
import UserNotifications

/// Schedules the phone's Smart Trash reminders as **pre-planned local
/// notifications**, so they fire even with the app closed:
///
///   · one at 2 days before the nearest deadline,
///   · one at 1 day before,
///   · then every 3 hours through the final day until the deadline itself.
///
/// The whole series is cancelled and rebuilt on every candidate sync — review
/// the files and the next sync silently clears the remaining reminders; ignore
/// them and the escalation keeps firing as scheduled. No candidates → nothing
/// pending.
enum TrashReminder {
    private static let idPrefix = "fiple.trash.reminder."
    /// Escalation cadence through the final day.
    private static let finalDayInterval: TimeInterval = 3 * 3_600

    static func reschedule(for candidates: [TrashCandidate]) {
        let center = UNUserNotificationCenter.current()
        // Drop the whole previous series — reviewed candidates must stop firing.
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
        guard let nearest = candidates.map(\.deadline).min() else { return }

        let count = candidates.count
        var schedule: [(fireIn: TimeInterval, body: String)] = []

        func add(at fireDate: Date, _ body: String) {
            let interval = fireDate.timeIntervalSinceNow
            guard interval > 60 else { return } // already past — skip
            schedule.append((interval, body))
        }

        let files = count == 1 ? "1 file" : "\(count) files"
        add(at: nearest.addingTimeInterval(-2 * 86_400),
            "\(files) on your Mac move to the Trash in 2 days. Review them in Fiple.")
        add(at: nearest.addingTimeInterval(-86_400),
            "\(files) move to your Mac's Trash tomorrow. Review them in Fiple.")
        // The final day: escalate every 3 hours up to the deadline itself.
        var t = nearest.addingTimeInterval(-86_400 + finalDayInterval)
        while t <= nearest {
            let hoursLeft = max(0, Int(nearest.timeIntervalSince(t) / 3_600))
            add(at: t, hoursLeft == 0
                ? "\(files) are moving to your Mac's Trash now. They stay recoverable in the Trash."
                : "\(files) move to your Mac's Trash in \(hoursLeft)h. Review them in Fiple.")
            t.addTimeInterval(finalDayInterval)
        }

        guard !schedule.isEmpty else { return }
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            for (index, item) in schedule.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = "Smart Trash"
                content.body = item.body
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: item.fireIn, repeats: false)
                center.add(UNNotificationRequest(
                    identifier: "\(idPrefix)\(index)", content: content, trigger: trigger
                ))
            }
        }
    }
}
