import Observation
import SwiftUI

@MainActor
@Observable
final class RatingCardModel {
    enum Status: Equatable {
        case idle, sending, sent, failed(String)
    }

    var photoId = ""
    var authorName = ""
    var caption: String?
    var image: UIImage?
    var rating = MyRating(myStars: 0, mine: [])
    var status: Status = .idle

    /// Tapping the stars you already gave clears them.
    func tapStar(_ value: Int) async {
        let stars = value == rating.myStars ? 0 : value
        await send(MyRating(myStars: stars, mine: rating.mine)) {
            try await ReactionAPI.setStars(stars, photoId: $0)
        }
    }

    func toggle(_ kind: ReactionKind) async {
        let on = !rating.mine.contains(kind)
        let mine = on ? rating.mine + [kind] : rating.mine.filter { $0 != kind }
        await send(MyRating(myStars: rating.myStars, mine: mine)) {
            try await ReactionAPI.setReaction(kind, on: on, photoId: $0)
        }
    }

    private func send(_ optimistic: MyRating, request: (String) async throws -> MyRating) async {
        guard !photoId.isEmpty else { return }
        let previous = rating
        rating = optimistic
        status = .sending
        do {
            rating = try await request(photoId)
            status = .sent
            WidgetRefresh.now()
        } catch {
            rating = previous
            status = .failed(error.localizedDescription)
        }
    }
}

/// The long-pressed notification: who posted, the photo, stars 1–3, reactions and a status line.
/// The system draws its own material behind it in light or dark, so the card has no background
/// and its text uses the system primary and secondary styles; the accent marks only your choice.
struct RatingCard: View {
    private static let padding = Space.gap
    private static let spacing: CGFloat = 12
    private static let rowSpacing: CGFloat = 8
    private static let statusHeight: CGFloat = 20

    /// Height of everything except the square photo, used for preferredContentSize:
    /// the padding, the header, two button rows, the status line and the gaps between them.
    static let extraHeight: CGFloat = padding * 2
        + Space.hitTarget
        + Space.controlHeight * 2 + rowSpacing
        + statusHeight
        + spacing * 3

    let model: RatingCardModel
    let openApp: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            header
            photo
            VStack(spacing: Self.rowSpacing) {
                HStack(spacing: Self.rowSpacing) {
                    ForEach(1...Stars.max, id: \.self) { value in
                        star(value)
                    }
                }
                HStack(spacing: Self.rowSpacing) {
                    ForEach(ReactionKind.allCases) { kind in
                        reaction(kind)
                    }
                }
            }
            status
        }
        .padding(Self.padding)
        .sensoryFeedback(.selection, trigger: model.rating)
        .onChange(of: model.status) { _, status in
            switch status {
            case .sent, .failed:
                AccessibilityNotification.Announcement(statusText).post()
            case .idle, .sending:
                break
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(model.authorName)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            Button(action: openApp) {
                Text("Открыть")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(minWidth: Space.hitTarget, minHeight: Space.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Открывает фото в Locket")
        }
        .frame(minHeight: Space.hitTarget)
    }

    private var photo: some View {
        Color.primary.opacity(0.08)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = model.image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .overlay(alignment: .bottom) {
                if let caption = model.caption {
                    Text(caption)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(photoLabel)
    }

    private var photoLabel: String {
        guard let caption = model.caption else { return "Фото" }
        return "Фото с подписью «\(caption)»"
    }

    private func star(_ value: Int) -> some View {
        let lit = value <= model.rating.myStars
        return Button {
            Task { await model.tapStar(value) }
        } label: {
            Image(systemName: lit ? "star.fill" : "star")
                .font(.title3.weight(.semibold))
                .foregroundStyle(lit ? Palette.accent : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: Space.controlHeight)
                .background(Color.primary.opacity(0.08), in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value) из \(Stars.max)")
        .accessibilityAddTraits(lit ? .isSelected : [])
    }

    private func reaction(_ kind: ReactionKind) -> some View {
        let active = model.rating.mine.contains(kind)
        return Button {
            Task { await model.toggle(kind) }
        } label: {
            Text(kind.emoji)
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: Space.controlHeight)
                .background(active ? Palette.accent.opacity(0.3) : Color.primary.opacity(0.08), in: shape)
                .overlay(shape.strokeBorder(active ? Palette.accent : Color.clear, lineWidth: 1.5))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder
    private var status: some View {
        if case .failed = model.status {
            Label(statusText, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(Palette.negative)
                .frame(maxWidth: .infinity, minHeight: Self.statusHeight, alignment: .leading)
        } else {
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: Self.statusHeight, alignment: .leading)
        }
    }

    private var statusText: String {
        switch model.status {
        case .idle: return "Поставь оценку — приложение открывать не нужно"
        case .sending: return "Сохраняю…"
        case .sent: return "Оценка сохранена"
        case .failed(let message): return Self.sentence(message) + " Попробуй ещё раз."
        }
    }

    /// Server messages usually end with a full stop; add one when they don't.
    private static func sentence(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return "Не получилось." }
        return ".!?…".contains(last) ? trimmed : trimmed + "."
    }
}
