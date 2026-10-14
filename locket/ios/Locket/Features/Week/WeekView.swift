import SwiftUI

struct WeekView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let week = model.currentWeek {
                        CountdownCard(week: week)
                        NominationsGrid(results: week, live: true)
                        if let best = week.bestPhoto {
                            BestPhotoCard(best: best, live: true)
                        }
                        LeaderboardSection(standings: week.leaderboard, myId: model.myId)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }

                    if !model.history.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Прошлые недели").font(.title3.bold())
                            ForEach(model.history) { week in
                                NavigationLink(value: week) { HistoryRow(week: week) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }

                    RulesCard(endDate: model.currentWeek?.endDate)
                }
                .padding(16)
            }
            .refreshable { await model.refreshWeek() }
            .navigationTitle("Неделя")
            .navigationDestination(for: WeekResults.self) { WeekResultsView(results: $0) }
        }
    }
}

/// Results of a finished week; also opened from the "🏆 Итоги недели" push.
struct WeekResultsView: View {
    @Environment(AppModel.self) private var model
    let results: WeekResults

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("🏆 Итоги недели").font(.largeTitle.bold())
                    Text(results.rangeTitle).foregroundStyle(.secondary)
                }
                if let friend = results.friendOfWeek {
                    FriendOfWeekBanner(nominee: friend)
                }
                if let best = results.bestPhoto {
                    BestPhotoCard(best: best, live: false)
                }
                NominationsGrid(results: results, live: false)
                LeaderboardSection(standings: results.leaderboard, myId: model.myId)
            }
            .padding(16)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CountdownCard: View {
    let week: WeekResults

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Итоги — \(week.endDate.formatted(.dateTime.weekday(.wide).hour().minute().locale(.ru)))")
                .font(.headline)
            Text("Осталось: \(Text(week.endDate, style: .relative))")
                .font(.title2.weight(.heavy))
                .monospacedDigit()
            Text("\(week.photoCount ?? 0) фото на этой неделе")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.locketYellow.opacity(0.35), Color.locketYellow.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

private struct FriendOfWeekBanner: View {
    let nominee: Nominee

    var body: some View {
        HStack(spacing: 16) {
            Avatar(name: nominee.name, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("👑 Друг недели").font(.subheadline.weight(.semibold)).foregroundStyle(.black.opacity(0.7))
                Text(nominee.name).font(.title.bold()).foregroundStyle(.black)
                Text(Russian.points(nominee.value)).font(.subheadline).foregroundStyle(.black.opacity(0.7))
            }
            Spacer()
        }
        .padding(18)
        .background(Color.locketYellow, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct NominationsGrid: View {
    let results: WeekResults
    let live: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(live ? "Сейчас лидируют" : "Номинации").font(.title3.bold())
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                NominationTile(emoji: "👑", title: "Друг недели", nominee: results.friendOfWeek) { Russian.points($0) }
                ForEach(ReactionKind.allCases) { kind in
                    NominationTile(emoji: kind.emoji, title: kind.nomination, nominee: nominee(for: kind)) { "\($0) \(kind.emoji)" }
                }
                NominationTile(emoji: "⚡️", title: "Самый активный", nominee: results.mostActive) { Russian.points($0) }
            }
        }
    }
}

private extension NominationsGrid {
    func nominee(for kind: ReactionKind) -> Nominee? {
        switch kind {
        case .creative: return results.mostCreative
        case .funny: return results.mostFunny
        case .wild: return results.mostWild
        }
    }
}

private struct NominationTile: View {
    let emoji: String
    let title: String
    let nominee: Nominee?
    let detail: (Int) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(emoji).font(.system(size: 32))
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let nominee {
                Text(nominee.name).font(.headline).lineLimit(1)
                Text(detail(nominee.value)).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("пока никого").font(.headline).foregroundStyle(.secondary)
                Text(" ").font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct BestPhotoCard: View {
    let best: BestPhoto
    let live: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(live ? "📸 Лучшее фото пока" : "📸 Фото недели").font(.title3.bold())
            SquarePhoto(url: best.imageUrl, cornerRadius: 32)
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 8) {
                        Avatar(name: best.authorName, size: 28)
                        Text(best.authorName).font(.headline)
                    }
                    .padding(.leading, 6)
                    .padding(.trailing, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(14)
                }
            HStack(spacing: 14) {
                Text("⭐ \(best.stars)")
                Text("✍️ \(best.creative)")
                Text("😂 \(best.funny)")
                Text("🫪 \(best.wild)")
                Spacer()
                Text("\(best.starCount) \(Russian.plural(best.starCount, "оценка", "оценки", "оценок"))")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
            if let caption = best.caption, !caption.isEmpty {
                Text("«\(caption)»").italic().foregroundStyle(.secondary)
            }
        }
    }
}

private struct LeaderboardSection: View {
    let standings: [Standing]
    let myId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Таблица очков").font(.title3.bold())
            VStack(spacing: 0) {
                ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
                    HStack(spacing: 12) {
                        Text(place(index)).font(.headline).frame(width: 28)
                        Avatar(name: standing.name, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(standing.userId == myId ? "\(standing.name) (ты)" : standing.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text("📸 \(standing.posts)  ⭐ \(standing.stars)  ✍️ \(standing.creative)  😂 \(standing.funny)  🫪 \(standing.wild)  🗳 \(standing.given)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(standing.points)").font(.title3.weight(.heavy)).monospacedDigit()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    if index < standings.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func place(_ index: Int) -> String {
        let medals = ["🥇", "🥈", "🥉"]
        return index < medals.count ? medals[index] : "\(index + 1)"
    }
}

private struct HistoryRow: View {
    let week: WeekResults

    var body: some View {
        HStack(spacing: 12) {
            Color.card
                .frame(width: 56, height: 56)
                .overlay {
                    if let url = week.bestPhoto?.imageUrl {
                        RemoteImage(url: url)
                    } else {
                        Text("🏆")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(week.rangeTitle).font(.headline)
                Text(week.friendOfWeek.map { "👑 \($0.name)" } ?? "без победителя")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct RulesCard: View {
    let endDate: Date?

    private var deadline: String {
        guard let endDate else { return "в конце недели" }
        return endDate.formatted(.dateTime.weekday(.wide).hour().minute().locale(.ru))
    }

    var body: some View {
        DisclosureGroup("Как считаются очки") {
            VStack(alignment: .leading, spacing: 10) {
                Text("• Каждая ⭐ на твоём фото — 1 очко")
                Text("• Каждая ✍️, 😂 или 🫪 на твоём фото — 1 очко")
                Text("• Своё фото — 2 очка (в зачёт идут до 14 фото за неделю)")
                Text("• Каждая твоя оценка или реакция друзьям — 1 очко")
                Divider()
                Text("👑 Друг недели — больше всех очков")
                Text("📸 Фото недели — больше всех звёзд")
                Text("✍️ Креативный, 😂 смешной, 🫪 безбашенный — больше всех таких реакций")
                Text("⚡️ Активный — фото + оценки друзьям")
                Divider()
                Text("Итоги подводятся автоматически (\(deadline)). Оценивать можно только фото текущей недели, свои — нельзя.")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.top, 10)
        }
        .tint(.white)
        .padding(16)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
