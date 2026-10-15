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

struct RatingCard: View {
    /// Height of everything except the square photo, used for preferredContentSize.
    static let extraHeight: CGFloat = 250

    let model: RatingCardModel
    let openApp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.authorName).font(.headline)
                Spacer()
                Button("Открыть", action: openApp)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.locketYellow)
            }

            Color.white.opacity(0.08)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image = model.image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        ProgressView()
                    }
                }
                .overlay(alignment: .bottom) {
                    if let caption = model.caption {
                        Text(caption)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.black.opacity(0.5), in: Capsule())
                            .padding(12)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            HStack(spacing: 8) {
                ForEach(1...Stars.max, id: \.self) { value in
                    let lit = value <= model.rating.myStars
                    Button {
                        Task { await model.tapStar(value) }
                    } label: {
                        Image(systemName: lit ? "star.fill" : "star")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(lit ? Color.locketYellow : Color.primary.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value) из \(Stars.max)")
                }
            }

            HStack(spacing: 8) {
                ForEach(ReactionKind.allCases) { kind in
                    let active = model.rating.mine.contains(kind)
                    Button {
                        Task { await model.toggle(kind) }
                    } label: {
                        Text(kind.emoji)
                            .font(.title2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                active ? Color.locketYellow.opacity(0.3) : Color.primary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(active ? Color.locketYellow : Color.clear, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(kind.title)
                }
            }

            Text(statusText)
                .font(.footnote)
                .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(16)
        .sensoryFeedback(.selection, trigger: model.rating)
    }

    private var statusIsError: Bool {
        if case .failed = model.status { return true }
        return false
    }

    private var statusText: String {
        switch model.status {
        case .idle: return "Поставь звёзды и реакции — приложение открывать не нужно"
        case .sending: return "Отправляю…"
        case .sent: return "Отправлено \(model.authorName) ✓"
        case .failed(let message): return message
        }
    }
}
