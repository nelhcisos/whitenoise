import UIKit
import UserNotifications

/// Notification categories. Identifiers must match server/src/push.js.
enum PushCategories {
    static let ratePhoto = "PHOTO_RATING"
    static let weeklyResults = "WEEKLY_RESULTS"

    static var all: Set<UNNotificationCategory> {
        // No .foreground and no .authenticationRequired: tapping a button rates
        // the photo in the background, right from the lock screen.
        let rateActions = ReactionKind.allCases.map { kind in
            UNNotificationAction(identifier: kind.notificationActionID, title: "\(kind.emoji) \(kind.title)", options: [])
        }
        let rate = UNNotificationCategory(
            identifier: ratePhoto,
            actions: rateActions,
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Новое фото от друга",
            options: []
        )
        let weekly = UNNotificationCategory(identifier: weeklyResults, actions: [], intentIdentifiers: [], options: [])
        return [rate, weekly]
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
