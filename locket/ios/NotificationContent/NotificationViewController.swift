import SwiftUI
import UIKit
import UserNotifications
import UserNotificationsUI

/// Shown when a "new photo" notification is long-pressed (also on the lock
/// screen): the photo, ⭐ 1–3 and ✍️ 😂 🫪. Taps go straight to the server.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private let model = RatingCardModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let host = UIHostingController(rootView: RatingCard(model: model) { [weak self] in
            self?.extensionContext?.performNotificationDefaultAction()
        })
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        guard width > 0 else { return }
        // Square photo plus header, two button rows and the status line.
        let size = CGSize(width: width, height: width + RatingCard.extraHeight)
        if preferredContentSize != size { preferredContentSize = size }
    }

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        let info = content.userInfo
        model.photoId = info["photoId"] as? String ?? ""
        model.authorName = info["authorName"] as? String ?? content.title
        model.caption = (info["caption"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        if let attachment = content.attachments.first, let image = Self.loadImage(attachment.url) {
            model.image = image
        } else if let link = info["imageUrl"] as? String, let url = URL(string: link) {
            Task { [model] in
                if let result = try? await URLSession.shared.data(from: url), let image = UIImage(data: result.0) {
                    model.image = image
                } else {
                    model.imageFailed = true
                }
            }
        }
    }

    private static func loadImage(_ url: URL) -> UIImage? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return UIImage(contentsOfFile: url.path)
    }
}
