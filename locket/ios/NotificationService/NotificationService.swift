import Foundation
import UniformTypeIdentifiers
import UserNotifications

/// Runs for every push with "mutable-content": downloads the photo so the
/// notification shows it (the NotificationContent extension reuses it on long-press),
/// and hands a friend's new photo to the home-screen widget right away.
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
                    Self.updateWidget(info, imageData: data)
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

    private static func updateWidget(_ info: [AnyHashable: Any], imageData: Data) {
        guard let photoId = info["photoId"] as? String, let authorName = info["authorName"] as? String else { return }
        let createdAt = (info["createdAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        let caption = (info["caption"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let photo = WidgetPhoto(
            photoId: photoId,
            authorName: authorName,
            caption: caption,
            createdAt: createdAt,
            myStars: 0,
            mine: [],
            canReact: true
        )
        SharedPhotoStore.save(photo, imageData: imageData)
    }
}
