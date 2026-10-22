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

    /// The notification was tapped, or "Принять" was pressed on a friend request (ratings themselves
    /// are sent by the NotificationContent extension). An action may launch the app in the background:
    /// the completion handler is called only after the request finishes, so iOS keeps the app alive for it.
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
