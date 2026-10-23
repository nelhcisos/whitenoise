import SwiftUI
import UIKit
import UserNotifications
import UserNotificationsUI

/// Shown when a notification is long-pressed (also on the lock screen):
/// - a new photo: the photo, ⭐ 1–3 and ✍️ 😂 🫪;
/// - the evening «Оцени свой день»: 1–5 stars and what got in the way;
/// - «Кто лучше?»: two friends, pick one.
/// Taps go straight to the server; the app stays closed.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private let model = RatingCardModel()
    private let dayModel = DayCardModel()
    private let duelModel = DuelCardModel()
    /// The day and duel cards report their own height; the photo card is computed.
    private var isMeasured = false
    private var cardHeight: CGFloat = 0
    private var host: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    /// The card is chosen by the notification's category, which arrives after viewDidLoad.
    private func embed<Content: View>(_ content: Content) {
        guard host == nil else { return }
        let host = UIHostingController(rootView: content)
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
        self.host = host
    }

    private func openApp() {
        extensionContext?.performNotificationDefaultAction()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        guard width > 0 else { return }
        let size: CGSize
        if isMeasured {
            // The day card grows with its chips; both cards report their own height.
            size = CGSize(width: width, height: max(cardHeight, 160))
        } else {
            // Square photo plus header, two button rows and the status line.
            size = CGSize(width: width, height: width + RatingCard.extraHeight)
        }
        if preferredContentSize != size { preferredContentSize = size }
    }

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        if content.categoryIdentifier == DayReminderID.category {
            isMeasured = true
            dayModel.show(day: notification.date)
            embed(DayRatingCard(model: dayModel, openApp: { [weak self] in self?.openApp() }, onHeight: { [weak self] height in
                self?.cardHeightChanged(height)
            }))
            view.setNeedsLayout()
            return
        }
        if content.categoryIdentifier == DuelID.category {
            isMeasured = true
            duelModel.duel = Self.duel(from: content.userInfo)
            embed(DuelCard(model: duelModel, openApp: { [weak self] in self?.openApp() }, onHeight: { [weak self] height in
                self?.cardHeightChanged(height)
            }))
            view.setNeedsLayout()
            return
        }
        embed(RatingCard(model: model) { [weak self] in self?.openApp() })
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

    private func cardHeightChanged(_ height: CGFloat) {
        guard abs(cardHeight - height) > 0.5 else { return }
        cardHeight = height
        view.setNeedsLayout()
    }

    /// The push's duelId, left and right ({id, username}).
    private static func duel(from info: [AnyHashable: Any]) -> Duel? {
        func person(_ key: String) -> DuelPerson? {
            guard let raw = info[key] as? [String: Any],
                  let id = raw["id"] as? String,
                  let username = raw["username"] as? String else { return nil }
            return DuelPerson(id: id, username: username)
        }
        guard let id = info["duelId"] as? String, let left = person("left"), let right = person("right") else { return nil }
        return Duel(id: id, date: "", left: left, right: right, choice: nil)
    }

    private static func loadImage(_ url: URL) -> UIImage? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return UIImage(contentsOfFile: url.path)
    }
}
