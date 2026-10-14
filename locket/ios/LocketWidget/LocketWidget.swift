import AppIntents
import SwiftUI
import WidgetKit

@main
struct LocketWidgetBundle: WidgetBundle {
    var body: some Widget {
        FriendPhotoWidget()
    }
}

/// Locket-style home-screen widget: the newest photo from a friend,
/// with 🔥 🎨 😂 buttons on the medium and large sizes (iOS 17 interactive widgets).
struct FriendPhotoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FriendPhoto", provider: PhotoProvider()) { entry in
            FriendPhotoView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
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
}

struct PhotoProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhotoEntry {
        PhotoEntry(date: .now, photo: nil, image: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PhotoEntry) -> Void) {
        completion(currentEntry())
    }

    // The app and the notification extension call reloadAllTimelines() when
    // there is a new photo, so no periodic refresh is needed.
    func getTimeline(in context: Context, completion: @escaping (Timeline<PhotoEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> PhotoEntry {
        let image = SharedPhotoStore.imageURL.flatMap { UIImage(contentsOfFile: $0.path) }
        return PhotoEntry(date: .now, photo: SharedPhotoStore.load(), image: image)
    }
}

struct FriendPhotoView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PhotoEntry

    var body: some View {
        if let photo = entry.photo, let image = entry.image {
            content(photo, image)
                .widgetURL(URL(string: "locket://photo/\(photo.photoId)"))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.title)
                    .foregroundStyle(Color.locketYellow)
                Text("Здесь появятся фото друзей")
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func content(_ photo: WidgetPhoto, _ image: UIImage) -> some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 12) {
                filledImage(image)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(photo.authorName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let caption = photo.caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                    }
                    Text(photo.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength: 0)
                    if photo.canReact { ratingButtons(photo) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
        default:
            ZStack(alignment: .bottom) {
                filledImage(image)
                VStack(spacing: 8) {
                    if family == .systemLarge, let caption = photo.caption {
                        Text(caption)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.5), in: Capsule())
                    }
                    HStack {
                        Text(photo.authorName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.5), in: Capsule())
                        Spacer(minLength: 0)
                    }
                    if family == .systemLarge && photo.canReact {
                        ratingButtons(photo)
                    }
                }
                .padding(12)
            }
        }
    }

    private func filledImage(_ image: UIImage) -> some View {
        Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
    }

    private func ratingButtons(_ photo: WidgetPhoto) -> some View {
        HStack(spacing: 8) {
            ForEach(ReactionKind.allCases) { kind in
                Button(intent: RatePhotoIntent(photoId: photo.photoId, kind: kind)) {
                    Text(kind.emoji)
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            photo.mine.contains(kind) ? Color.locketYellow : Color.black.opacity(0.45),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 🔥 / 🎨 / 😂 on the widget: toggles the rating without opening the app.
struct RatePhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "Оценить фото"

    @Parameter(title: "Фото")
    var photoId: String

    @Parameter(title: "Оценка")
    var kind: String

    init() {}

    init(photoId: String, kind: ReactionKind) {
        self.photoId = photoId
        self.kind = kind.rawValue
    }

    func perform() async throws -> some IntentResult {
        guard let reaction = ReactionKind(rawValue: kind) else { return .result() }
        let alreadyOn = SharedPhotoStore.load()?.mine.contains(reaction) ?? false
        let mine = try await ReactionAPI.set(reaction, on: !alreadyOn, photoId: photoId)
        SharedPhotoStore.updateReactions(photoId: photoId, mine: mine)
        return .result()
    }
}
