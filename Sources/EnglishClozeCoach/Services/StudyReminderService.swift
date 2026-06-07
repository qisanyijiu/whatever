import Foundation
@preconcurrency import UserNotifications

struct StudyReminderService {
    private let reminderIdentifier = "whatever.daily-study-reminder"

    func syncDailyReminder(enabled: Bool, hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])

        guard enabled else {
            return
        }

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "whatever"
            content.body = "今天的英文填空还在等你。"
            content.sound = .default

            var dateComponents = DateComponents()
            dateComponents.hour = max(0, min(23, hour))
            dateComponents.minute = max(0, min(59, minute))

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: reminderIdentifier,
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
}
