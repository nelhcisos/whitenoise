import Foundation
import UniformTypeIdentifiers
import UserNotifications

/// Runs for every push with "mutable-content": downloads the photo so the
/// notification shows it (the NotificationContent extension reuses it on long-press),
/// and nudges the home-screen widget to pick up a friend's new photo right away.
final class NotificationService: UNNotificationServiceExtension {
    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?
    private var download: URLSessionDataTask?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        self.contentHandler = contentHandler
        self.content = content

        let info = request.content.userInfo
        guard let link = info["imageUrl"] as? String, !link.isEmpty, let url = URL(string: link) else {
            finish()
            return
        }

        download = URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard let self else { return }
            if let data, (response as? HTTPURLResponse)?.statusCode == 200 {
                if let attachment = Self.makeAttachment(data) {
                    content.attachments = [attachment]
                }
                if info["type"] as? String == "photo" {
                    WidgetRefresh.now()
                }
            }
            self.finish()
        }
        download?.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        download?.cancel()
        finish()
    }

    /// Delivers the notification exactly once, whichever path gets here first.
    private func finish() {
        lock.lock()
        let handler = contentHandler
        contentHandler = nil
        lock.unlock()
        if let handler, let content { handler(content) }
    }

    private static func makeAttachment(_ data: Data) -> UNNotificationAttachment? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent("photo.jpg")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file)
            return try UNNotificationAttachment(
                identifier: "photo",
                url: file,
                options: [UNNotificationAttachmentOptionsTypeHintKey: UTType.jpeg.identifier]
            )
        } catch {
            return nil
        }
    }
}
