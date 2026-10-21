import AppIntents
import ImageIO
import SwiftUI
import WidgetKit

@main
struct LocketWidgetBundle: WidgetBundle {
    var body: some Widget {
        FriendPhotoWidget()
    }
}

/// Locket-style home-screen widget: the newest photo from a friend,
/// with stars 1–3 and ✍️ 😂 🫪 buttons on the medium and large sizes (iOS 17 interactive widgets).
struct FriendPhotoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FriendPhoto", provider: PhotoProvider()) { entry in
            FriendPhotoView(entry: entry)
                .containerBackground(for: .widget) { Palette.ground }
                .environment(\.locale, .ru)
        }
        .configurationDisplayName("Фото друзей")
        .description("Последнее фото из компании и кнопки оценки.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct PhotoEntry: TimelineEntry {
    let date: Date
    let photo: WidgetPhoto?
    let image: UIImage?
    /// No session: the widget asks to sign in instead of promising a photo.
    var signedOut = false
    /// A tap on the buttons that didn't save, shown with them.
    var failure: String? = nil
}

struct PhotoProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhotoEntry {
        PhotoEntry(date: .now, photo: nil, image: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PhotoEntry) -> Void) {
        completion(WidgetStore.cachedEntry())
    }

    // The app and the notification extension also ask for a reload when a
    // friend posts, so the half-hour refresh is only a fallback.
    func getTimeline(in context: Context, completion: @escaping (Timeline<PhotoEntry>) -> Void) {
        Task {
            let entry = await WidgetStore.fetch()
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }
}

/// The newest photo from a friend, as GET /api/widget returns it.
struct WidgetPhoto: Codable, Equatable {
    let id: String
    let authorName: String
    let caption: String?
    let createdAt: Double
    let imageUrl: URL
    var canReact: Bool
    var myStars: Int
    var mine: [ReactionKind]
}

/// Loads the photo from the server and keeps the last one in the widget's own
/// caches folder, so it still shows something offline.
enum WidgetStore {
    private struct Response: Decodable { let photo: WidgetPhoto? }

    /// A tap that didn't save, for the photo it was about.
    private struct SavedFailure: Codable {
        let photoId: String
        let message: String
        let date: Date
    }

    private static var folder: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0] }
    private static var metaURL: URL { folder.appendingPathComponent("widget-photo.json") }
    private static var imageURL: URL { folder.appendingPathComponent("widget-photo.jpg") }
    private static var failureURL: URL { folder.appendingPathComponent("widget-failure.json") }

    /// WidgetKit reloads the timeline as soon as a button's intent returns, so a fetch
    /// clears a failure only once it has been on screen for a while.
    private static let failureMinAge: TimeInterval = 60

    static func cached() -> WidgetPhoto? {
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        return try? JSONDecoder().decode(WidgetPhoto.self, from: data)
    }

    static func cachedEntry() -> PhotoEntry {
        let photo = cached()
        var failure: String?
        if let saved = cachedFailure(), saved.photoId == photo?.id { failure = saved.message }
        return PhotoEntry(date: .now, photo: photo, image: UIImage(contentsOfFile: imageURL.path), failure: failure)
    }

    static func fetch() async -> PhotoEntry {
        guard let token = TokenStore.token else { return PhotoEntry(date: .now, photo: nil, image: nil, signedOut: true) }
        var request = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent("api/widget"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: result.0)
        else { return cachedEntry() }

        if let saved = cachedFailure(), Date.now.timeIntervalSince(saved.date) > failureMinAge {
            clearFailure()
        }
        guard let photo = decoded.photo else {
            try? FileManager.default.removeItem(at: metaURL)
            try? FileManager.default.removeItem(at: imageURL)
            return PhotoEntry(date: .now, photo: nil, image: nil)
        }
        if cached()?.id != photo.id || !FileManager.default.fileExists(atPath: imageURL.path) {
            guard let download = try? await URLSession.shared.data(from: photo.imageUrl),
                  let thumbnail = thumbnail(download.0)
            else { return cachedEntry() }
            try? thumbnail.write(to: imageURL, options: .atomic)
        }
        save(photo)
        return cachedEntry()
    }

    static func save(_ photo: WidgetPhoto) {
        if let data = try? JSONEncoder().encode(photo) { try? data.write(to: metaURL, options: .atomic) }
    }

    /// After a tap on the widget, so the next render shows it even before the refetch.
    static func remember(_ rating: MyRating, photoId: String) {
        guard var photo = cached(), photo.id == photoId else { return }
        photo.myStars = rating.myStars
        photo.mine = rating.mine
        save(photo)
        clearFailure()
    }

    /// WidgetKit drops errors thrown by a widget button, so the widget shows them itself.
    static func rememberFailure(_ error: Error, photoId: String) {
        var message = "Не сохранилось — нет связи. Нажми ещё раз."
        if let failure = error as? ReactionAPI.Failure, !failure.canRetry { message = failure.message }
        let saved = SavedFailure(photoId: photoId, message: message, date: .now)
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: failureURL, options: .atomic) }
    }

    private static func cachedFailure() -> SavedFailure? {
        guard let data = try? Data(contentsOf: failureURL) else { return nil }
        return try? JSONDecoder().decode(SavedFailure.self, from: data)
    }

    private static func clearFailure() {
        try? FileManager.default.removeItem(at: failureURL)
    }

    /// Widgets refuse to render large images, so keep a small copy.
    private static func thumbnail(_ data: Data, maxPixel: Int = 800) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.85)
    }
}

struct FriendPhotoView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PhotoEntry

    var body: some View {
        if let photo = entry.photo, let image = entry.image {
            content(photo, image)
                .widgetURL(URL(string: "locket://photo/\(photo.id)"))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Locket")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Palette.text)
                Text(emptyText)
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(16)
            // Opens the app; it ignores a link with no host.
            .widgetURL(URL(string: "locket://"))
        }
    }

    private var emptyText: String {
        entry.signedOut ? "Войди в Locket, чтобы видеть фото друзей" : "Здесь появится фото, когда друг его выложит"
    }

    @ViewBuilder
    private func content(_ photo: WidgetPhoto, _ image: UIImage) -> some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 12) {
                filledImage(image, label: photo)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    if photo.canReact {
                        // Two 44 pt rows take 94 of the 124–146 pt inside a medium widget:
                        // above them is room for the name or a failed tap, not the caption.
                        Group {
                            if let failure = entry.failure {
                                failureLine(failure)
                            } else {
                                mediumName(photo)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        ratingButtons(photo)
                    } else {
                        mediumName(photo)
                        if let caption = photo.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.footnote)
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
        default:
            ZStack(alignment: .bottom) {
                filledImage(image, label: photo)
                VStack(alignment: .leading, spacing: 8) {
                    if family == .systemLarge, let caption = photo.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.headline)
                            .foregroundStyle(Palette.text)
                            .lineLimit(2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Palette.scrim, in: Capsule())
                    }
                    Text(photo.authorName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Palette.scrim, in: Capsule())
                    if family == .systemLarge && photo.canReact {
                        ratingButtons(photo)
                        if let failure = entry.failure {
                            failureLine(failure)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Palette.scrim, in: Capsule())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
    }

    private func filledImage(_ image: UIImage, label photo: WidgetPhoto) -> some View {
        Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Фото от \(photo.authorName)")
    }

    private func mediumName(_ photo: WidgetPhoto) -> some View {
        Text(photo.authorName)
            .font(.headline)
            .foregroundStyle(Palette.text)
            .lineLimit(1)
    }

    /// A tap that didn't save. The icon carries the colour and the text stays white,
    /// so it reads on the ground and on the photo's scrim alike.
    private func failureLine(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(Palette.negative)
        }
        .font(.footnote)
        .foregroundStyle(Palette.text)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
    }

    /// Stars 1–3 and the three reactions, 44 pt tall. Your choice is the accent (data):
    /// a filled star, a tinted and outlined reaction. The rest sit on the scrim.
    private func ratingButtons(_ photo: WidgetPhoto) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(1...Stars.max, id: \.self) { value in
                    let lit = value <= photo.myStars
                    Button(intent: RateStarsIntent(photoId: photo.id, stars: value)) {
                        Image(systemName: lit ? "star.fill" : "star")
                            .font(.headline)
                            .foregroundStyle(lit ? Palette.accent : Palette.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: Space.hitTarget)
                            .background(Palette.scrim, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value) из \(Stars.max)")
                    // Selected is your own pick only, not every lit star.
                    .accessibilityAddTraits(value == photo.myStars ? .isSelected : [])
                }
            }
            HStack(spacing: 6) {
                ForEach(ReactionKind.allCases) { kind in
                    let active = photo.mine.contains(kind)
                    Button(intent: RateReactionIntent(photoId: photo.id, kind: kind)) {
                        Text(kind.emoji)
                            .font(.headline)
                            .foregroundStyle(Palette.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: Space.hitTarget)
                            .background(active ? Palette.accentTint : Palette.scrim, in: Capsule())
                            .overlay(Capsule().strokeBorder(active ? Palette.accent : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(kind.title)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
        }
    }
}

/// Stars on the widget. Tapping the stars you already gave clears them.
struct RateStarsIntent: AppIntent {
    static let title: LocalizedStringResource = "Поставить звёзды"

    @Parameter(title: "Фото")
    var photoId: String

    @Parameter(title: "Звёзды")
    var stars: Int

    init() {}

    init(photoId: String, stars: Int) {
        self.photoId = photoId
        self.stars = stars
    }

    func perform() async throws -> some IntentResult {
        let current = WidgetStore.cached().flatMap { $0.id == photoId ? $0.myStars : nil } ?? 0
        do {
            let rating = try await ReactionAPI.setStars(stars == current ? 0 : stars, photoId: photoId)
            WidgetStore.remember(rating, photoId: photoId)
        } catch {
            WidgetStore.rememberFailure(error, photoId: photoId)
            WidgetRefresh.now()
        }
        return .result()
    }
}

/// ✍️ / 😂 / 🫪 on the widget: toggles the reaction without opening the app.
struct RateReactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Отреагировать на фото"

    @Parameter(title: "Фото")
    var photoId: String

    @Parameter(title: "Реакция")
    var kind: String

    init() {}

    init(photoId: String, kind: ReactionKind) {
        self.photoId = photoId
        self.kind = kind.rawValue
    }

    func perform() async throws -> some IntentResult {
        guard let reaction = ReactionKind(rawValue: kind) else { return .result() }
        let alreadyOn = WidgetStore.cached().map { $0.id == photoId && $0.mine.contains(reaction) } ?? false
        do {
            let rating = try await ReactionAPI.setReaction(reaction, on: !alreadyOn, photoId: photoId)
            WidgetStore.remember(rating, photoId: photoId)
        } catch {
            WidgetStore.rememberFailure(error, photoId: photoId)
            WidgetRefresh.now()
        }
        return .result()
    }
}
