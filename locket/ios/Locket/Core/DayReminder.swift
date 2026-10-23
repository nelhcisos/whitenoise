import Foundation
import UserNotifications

/// The evening «Оцени свой день, как поездку» notification. It's scheduled on the
/// phone itself, at the same time every day (23:00 unless changed in the «День» tab),
/// so it needs no server and arrives on time in any time zone.
enum DayReminder {
    static let defaultMinutes = 23 * 60
    private static let minutesKey = "dayReminderMinutes"
    private static let enabledKey = "dayReminderEnabled"

    /// Minutes after midnight.
    static var minutes: Int {
        get { UserDefaults.standard.object(forKey: minutesKey) as? Int ?? defaultMinutes }
        set { UserDefaults.standard.set(newValue, forKey: minutesKey) }
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// «23:00»
    static var timeText: String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// Replaces the daily notification with one at the current time, or removes it when off.
    static func schedule() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [DayReminderID.daily])
        guard isEnabled else { return }
        var time = DateComponents()
        time.hour = minutes / 60
        time.minute = minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: DayReminderID.daily, content: content(), trigger: trigger))
    }

    /// One notification in five seconds: lock the phone and try the card right away.
    /// Returns false when notifications are not allowed.
    static func sendTest() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: DayReminderID.test, content: content(), trigger: trigger))
        return true
    }

    private static func content() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Как прошёл день?"
        content.body = "Оцени его, как поездку: от 1 до 5 звёзд. Удерживай уведомление, чтобы оценить."
        content.sound = .default
        content.categoryIdentifier = DayReminderID.category
        content.threadIdentifier = "day"
        content.userInfo = ["type": "day"]
        return content
    }
}
