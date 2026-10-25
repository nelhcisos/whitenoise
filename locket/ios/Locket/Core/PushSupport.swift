import UIKit
import UserNotifications

/// Notification categories. Identifiers must match server/src/push.js.
enum PushCategories {
    static let ratePhoto = "PHOTO_RATING"
    static let weeklyResults = "WEEKLY_RESULTS"
    static let friendRequest = "FRIEND_REQUEST"
    /// "Принять" on a friend request: runs in the background, even from the lock screen.
    static let acceptFriendAction = "ACCEPT_FRIEND"
    static let birthday = "BIRTHDAY"
    /// "Открыть виш-лист" on a birthday: opens the app on that friend's wishlist.
    static let openWishlistAction = "OPEN_WISHLIST"

    static var all: Set<UNNotificationCategory> {
        // Photos have no action buttons: a long-press opens the NotificationContent extension,
        // which shows the photo with ⭐ 1–3 and ✍️ 😂 🫪 and sends ratings itself.
        let rate = UNNotificationCategory(
            identifier: ratePhoto,
            actions: [],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Новое фото от друга",
            options: []
        )
        let weekly = UNNotificationCategory(identifier: weeklyResults, actions: [], intentIdentifiers: [], options: [])
        let accept = UNNotificationAction(identifier: acceptFriendAction, title: "Принять", options: [])
        let friend = UNNotificationCategory(identifier: friendRequest, actions: [accept], intentIdentifiers: [], options: [])
        // The evening «Оцени свой день»: a long-press opens the stars 1–5 card.
        let day = UNNotificationCategory(
            identifier: DayReminderID.category,
            actions: [],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Оцени свой день",
            options: []
        )
        // «Кто лучше?»: a long-press shows the two friends to pick from.
        let duel = UNNotificationCategory(
            identifier: DuelID.category,
            actions: [],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Кто лучше?",
            options: []
        )
        // A friend's birthday (a month before, 5 days before, on the day).
        let wishlist = UNNotificationAction(identifier: openWishlistAction, title: "Открыть виш-лист", options: [.foreground])
        let birthdayCategory = UNNotificationCategory(
            identifier: birthday,
            actions: [wishlist],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "День рождения друга",
            options: []
        )
        return [rate, weekly, friend, day, duel, birthdayCategory]
    }
}

@MainActor
enum PushRegistrar {
    /// Debug builds from Xcode get sandbox tokens, TestFlight/App Store builds production ones.
    static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    static func requestPermissionAndRegister() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
