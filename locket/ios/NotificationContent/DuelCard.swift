import Observation
import SwiftUI

@MainActor
@Observable
final class DuelCardModel {
    enum Status: Equatable {
        case idle, sending, sent, failed(String, canRetry: Bool)
    }

    var duel: Duel?
    var status: Status = .idle

    func choose(_ pick: DuelPick) async {
        guard let current = duel, current.choice == nil, status != .sending else { return }
        // Show the pick at once; put it back if the server says no.
        var optimistic = current
        optimistic.choice = pick.rawValue
        duel = optimistic
        status = .sending
        do {
            duel = try await DuelAPI.choose(duelId: current.id, pick: pick)
            status = .sent
        } catch {
            duel = current
            let canRetry = (error as? ReactionAPI.Failure)?.canRetry ?? true
            status = .failed(error.localizedDescription, canRetry: canRetry)
        }
    }
}

/// The long-pressed «Кто лучше?» notification: two friends, pick one.
struct DuelCard: View {
    let model: DuelCardModel
    let openApp: () -> Void
    /// Reports the card's natural height for the notification's size.
    let onHeight: (CGFloat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Кто лучше?")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Выбери одного — кого не выбрал, никто не узнает")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: openApp) {
                    Text("Открыть Locket")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(minHeight: Space.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let duel = model.duel {
                DuelChoiceView(duel: duel, busy: model.status == .sending) { pick in
                    Task { await model.choose(pick) }
                }
            }
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
        .sensoryFeedback(.selection, trigger: model.duel?.choice)
        .onChange(of: model.status) { _, status in
            switch status {
            case .sent, .failed:
                AccessibilityNotification.Announcement(statusText).post()
            case .idle, .sending:
                break
            }
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
        case .idle: return "Левый или правый — приложение открывать не нужно"
        case .sending: return "Сохраняю…"
        case .sent:
            guard let name = model.duel?.chosen?.username else { return "Выбор сохранён" }
            return "Выбор сохранён: \(name)"
        case .failed(let message, let canRetry):
            let text = message.hasSuffix(".") || message.hasSuffix("…") ? message : message + "."
            return canRetry ? text + " Попробуй ещё раз." : text
        }
    }
}
