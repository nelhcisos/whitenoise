import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(PushCategories.all)
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await AppModel.shared.registerDevice(token: token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push registration failed: \(error.localizedDescription)")
    }

    /// A push arrived while Locket is open: still show it, and refresh the data behind it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let push = PushInfo(notification.request.content.userInfo)
        Task { @MainActor in AppModel.shared.pushArrived(push) }
        completionHandler([.banner, .list, .sound])
    }

    /// The notification itself or one of its 🔥 🎨 😂 buttons was tapped —
    /// possibly on the lock screen, with the app launched in the background.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let push = PushInfo(response.notification.request.content.userInfo)
        let action = response.actionIdentifier
        Task { @MainActor in
            await AppModel.shared.handleNotificationResponse(action: action, push: push)
            completionHandler()
        }
    }
}
