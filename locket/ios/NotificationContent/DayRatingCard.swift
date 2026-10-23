import Observation
import SwiftUI

@MainActor
@Observable
final class DayCardModel {
    enum Status: Equatable {
        case idle, sending, sent, failed(String, canRetry: Bool)
    }

    var rating = DayRating.blank(DayRating.key(for: Date()))
    var status: Status = .idle
    @ObservationIgnored private var pending: Task<Void, Never>?

    /// The notification's own date is the day being rated, even when answered after midnight.
    func show(day date: Date) {
        let key = DayRating.key(for: date)
        if rating.date != key { rating = DayRating.blank(key) }
    }

    /// Saves shortly after the last tap, so a quick run of taps is one request.
    func changed() {
        guard rating.stars > 0 else { return }
        pending?.cancel()
        status = .sending
        pending = Task {
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }
            do {
                let saved = try await DayAPI.save(rating)
                if Task.isCancelled { return }
                // Keep what the person is touching; take only what the server adds.
                rating.updatedAt = saved.updatedAt
                status = .sent
            } catch {
                if Task.isCancelled { return }
                let canRetry = (error as? ReactionAPI.Failure)?.canRetry ?? true
                status = .failed(error.localizedDescription, canRetry: canRetry)
            }
        }
    }
}

/// The long-pressed evening notification: «Оцени свой день, как поездку».
/// Like the photo card it sits on the system material, so it has no background of its own.
struct DayRatingCard: View {
    @Bindable var model: DayCardModel
    let openApp: () -> Void
    /// Reports the card's natural height, so the notification can grow with the chips.
    let onHeight: (CGFloat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            DayRatingForm(rating: $model.rating, onChange: { model.changed() })
            status
        }
        .padding(Space.gap)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onHeight(proxy.size.height) }
                    .onChange(of: proxy.size.height) { _, height in onHeight(height) }
            }
        )
        .frame(maxHeight: .infinity, alignment: .top)
        .sensoryFeedback(.selection, trigger: model.rating.stars)
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Оцени свой день")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(DayRating.title(of: model.rating.date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(action: openApp) {
                Text("Открыть Locket")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(minHeight: Space.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var status: some View {
        if case .failed = model.status {
            Label(statusText, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(Palette.negative)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch model.status {
        case .idle: return "Как поездку: от 1 до 5 звёзд, приложение открывать не нужно"
        case .sending: return "Сохраняю…"
        case .sent: return "Оценка дня сохранена"
        case .failed(let message, let canRetry):
            let text = message.hasSuffix(".") || message.hasSuffix("…") ? message : message + "."
            return canRetry ? text + " Попробуй ещё раз." : text
        }
    }
}
