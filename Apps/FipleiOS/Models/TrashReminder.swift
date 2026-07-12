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

    static func reschedule(for candidates: [TrashCandidate]) {
        let center = UNUserNotificationCenter.current()
        // Drop the whole previous series — reviewed candidates must stop firing.
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
        // Anchored on the nearest *future* deadline — an expired candidate the
        // Mac hasn't enforced yet must not collapse the whole series.
        let schedule = TrashReminderPlan.entries(for: candidates, now: Date())
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
