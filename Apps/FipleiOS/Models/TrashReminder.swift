import FipleKit
import Foundation
import UserNotifications

/// Schedules the phone's single Smart Trash reminder: one local notification at
/// (nearest deadline − 2 days), rescheduled on every candidate sync so it always
/// tracks the current list. No candidates → no pending notification.
enum TrashReminder {
    private static let id = "fiple.trash.reminder"

    static func reschedule(for candidates: [TrashCandidate]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let nearest = candidates.map(\.deadline).min() else { return }

        let fireDate = nearest.addingTimeInterval(-2 * 86_400)
        let interval = fireDate.timeIntervalSinceNow
        // Deadline already inside the 2-day window → nothing to schedule; the
        // review screen itself shows the countdown.
        guard interval > 0 else { return }

        center.requestAuthorization(options: [.alert, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Smart Trash"
            content.body = candidates.count == 1
                ? "1 file moves to your Mac's Trash soon. Review it in Fiple."
                : "\(candidates.count) files move to your Mac's Trash soon. Review them in Fiple."
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}
