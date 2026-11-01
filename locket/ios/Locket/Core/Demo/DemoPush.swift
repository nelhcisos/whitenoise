import UserNotifications

/// Browser demo only: what a real server would push, shown as a local notification.
enum DemoPush {
    /// барсук's password in the demo data.
    static let password = "1234"

    /// ярослава's birthday push, a couple of seconds after launch. Tapping it (or
    /// «Открыть виш-лист») opens her wishlist, exactly like the server's push.
    static func showBirthday() async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "Сегодня день рождения 🎂"
        content.body = "ярослава празднует — поздравь! Виш-лист — по нажатию"
        content.sound = .default
        content.categoryIdentifier = PushCategories.birthday
        content.threadIdentifier = "birthdays"
        content.userInfo = ["type": "birthday", "userId": "u-yara", "username": "ярослава", "daysLeft": 0]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "demo-birthday", content: content, trigger: trigger))
    }
}
