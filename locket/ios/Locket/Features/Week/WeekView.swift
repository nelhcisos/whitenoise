import SwiftUI

/// The current week: who leads and how long is left, then the nominations, the best photo,
/// the table, past weeks and the rules.
struct WeekView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    VStack(alignment: .leading, spacing: Space.gap) {
                        TimelineView(.everyMinute) { context in
                            ScreenTitle(title: "Неделя", subtitle: subtitle(at: context.date))
                        }
                        status
                    }
                    if let week = model.currentWeek, week.photoCount != 0 {
                        NominationsSection(results: week)
                        bestPhoto(of: week)
                        LeaderboardSection(standings: week.leaderboard, myId: model.myId)
                    }
                    if !model.history.isEmpty {
                        HistorySection(weeks: model.history)
                    }
                    RulesCard(deadline: endDate)
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.gap)
                .padding(.bottom, Space.section)
            }
            .background(Palette.ground)
            .safeAreaInset(edge: .top, spacing: 0) {
                // Keeps scrolled content from showing under the status bar.
                Color.clear
                    .frame(height: 0)
                    .background(Palette.ground, ignoresSafeAreaEdges: .top)
            }
            .refreshable { await model.refreshWeek() }
            .navigationTitle("Неделя")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: WeekResults.self) { WeekResultsView(results: $0) }
        }
    }

    /// The first block: who leads, or why that can't be shown yet.
    @ViewBuilder
    private var status: some View {
        if let failure {
            InlineError(message: failureMessage(failure)) {
                Task { await model.refreshWeek() }
            }
        }
        if let week = model.currentWeek {
            if week.photoCount == 0 {
                EmptyState(
                    text: "На этой неделе ещё нет фото — выложи первое.",
                    actionTitle: "Сделать фото",
                    action: { model.selectedTab = .camera }
                )
            } else {
                LeadCard(title: "Сейчас лидирует", nominee: week.friendOfWeek, emptyText: "Пока никто не набрал очков.")
            }
        } else if failure == nil {
            WeekSkeleton()
        }
    }

    @ViewBuilder
    private func bestPhoto(of week: WeekResults) -> some View {
        if let best = week.bestPhoto {
            BestPhotoSection(title: "Лучшее фото", best: best)
        } else {
            VStack(alignment: .leading, spacing: Space.header) {
                SectionHeader("Лучшее фото")
                EmptyState(
                    text: "Пока ни у одного фото нет звёзд.",
                    actionTitle: "Открыть ленту",
                    action: { model.selectedTab = .feed }
                )
            }
        }
    }

    private var failure: String? {
        if case .failed(let message) = model.weekState { return message }
        return nil
    }

    /// The week already on screen stays; the error then says it wasn't refreshed.
    private func failureMessage(_ reason: String) -> String {
        let what = model.currentWeek == nil ? "Не удалось загрузить неделю." : "Не удалось обновить неделю."
        return "\(what) \(reason)"
    }

    /// The week's end, known from the profile even before the week itself loads.
    private var endDate: Date? {
        if let week = model.currentWeek { return week.endDate }
        guard let week = model.me?.week else { return nil }
        return Date(timeIntervalSince1970: week.endsAt / 1000)
    }

    /// "Итоги в воскресенье в 21:00 · через 2 дня"
    private func subtitle(at now: Date) -> String? {
        guard let endDate else { return nil }
        guard let left = WeekDeadline.remaining(until: endDate, from: now) else { return "Подводим итоги…" }
        return "Итоги \(WeekDeadline.upcoming(endDate, from: now)) · \(left)"
    }
}

/// Results of a finished week: from past weeks and from the weekly results push.
struct WeekResultsView: View {
    @Environment(AppModel.self) private var model
    let results: WeekResults

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                VStack(alignment: .leading, spacing: Space.gap) {
                    ScreenTitle(title: "Итоги недели", subtitle: results.rangeTitle)
                    if results.photoCount == 0 {
                        EmptyState(text: "На этой неделе никто не выложил фото.")
                    } else {
                        LeadCard(title: "Друг недели", nominee: results.friendOfWeek, emptyText: "Никто не набрал очков.")
                    }
                }
                if results.photoCount != 0 {
                    if let best = results.bestPhoto {
                        BestPhotoSection(title: "Фото недели", best: best)
                    }
                    NominationsSection(results: results)
                    LeaderboardSection(standings: results.leaderboard, myId: model.myId)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.gap)
            .padding(.bottom, Space.section)
        }
        .background(Palette.ground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .groundBar(for: .navigationBar)
    }
}

// MARK: - Blocks

/// The answer to the screen's question: who leads and with how many points.
private struct LeadCard: View {
    let title: String
    let nominee: Nominee?
    let emptyText: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                if let nominee {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(nominee.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Text(WeekFormat.points(nominee.value))
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.text)
                            .fixedSize()
                    }
                } else {
                    Text(emptyText)
                        .font(.body)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Every nomination as one list: title, winner, and what they won it with.
private struct NominationsSection: View {
    let results: WeekResults

    var body: some View {
        VStack(alignment: .leading, spacing: Space.header) {
            SectionHeader("Номинации")
            // The friend of the week leads the screen in its own card, so it is not repeated here.
            Card {
                ForEach(ReactionKind.allCases) { kind in
                    NominationRow(mark: kind.emoji, title: kind.nomination, nominee: nominee(for: kind), value: WeekFormat.reactions)
                    WeekDivider()
                }
                NominationRow(title: "Самый активный", nominee: results.mostActive, value: WeekFormat.points)
            }
        }
    }

    private func nominee(for kind: ReactionKind) -> Nominee? {
        switch kind {
        case .creative: return results.mostCreative
        case .funny: return results.mostFunny
        case .wild: return results.mostWild
        }
    }
}

private struct NominationRow: View {
    /// The reaction's emoji, shown before the title but not read by VoiceOver.
    var mark: String? = nil
    let title: String
    let nominee: Nominee?
    let value: (Int) -> String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .accessibilityLabel(title)
                if let nominee {
                    Text(nominee.name)
                        .font(.body)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                } else {
                    Text("—")
                        .font(.body)
                        .foregroundStyle(Palette.faint)
                        .accessibilityLabel("никого")
                }
            }
            Spacer(minLength: 8)
            if let nominee {
                Text(value(nominee.value))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.muted)
                    .fixedSize()
            }
        }
        .frame(minHeight: Space.hitTarget)
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        guard let mark else { return title }
        return "\(mark) \(title)"
    }
}

/// The photo with the most stars, its author and what it collected.
private struct BestPhotoSection: View {
    let title: String
    let best: BestPhoto

    var body: some View {
        VStack(alignment: .leading, spacing: Space.header) {
            SectionHeader(title)
            SquarePhoto(url: best.imageUrl)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title), автор — \(best.authorName)")
                .accessibilityAddTraits(.isImage)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Avatar(name: best.authorName, size: AvatarSize.small)
                    Text(best.authorName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                }
                Text(summary(spoken: false))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.muted)
                    .accessibilityLabel(summary(spoken: true))
                if let caption = best.caption, !caption.isBlank {
                    Text("«\(caption)»")
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }

    /// "5 звёзд · 2 оценки · ✍️ 1 · 😂 0 · 🫪 1"; spoken, the reactions are named.
    private func summary(spoken: Bool) -> String {
        var parts = [WeekFormat.stars(best.stars), WeekFormat.ratings(best.starCount)]
        parts += ReactionKind.allCases.map { WeekFormat.mark($0, count(for: $0), spoken: spoken) }
        return parts.joined(separator: spoken ? ", " : " · ")
    }

    private func count(for kind: ReactionKind) -> Int {
        switch kind {
        case .creative: return best.creative
        case .funny: return best.funny
        case .wild: return best.wild
        }
    }
}

/// Everyone in the circle by points, with the breakdown under each name.
private struct LeaderboardSection: View {
    let standings: [Standing]
    let myId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.header) {
            SectionHeader("Таблица")
            Card {
                ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
                    if index > 0 { WeekDivider() }
                    StandingRow(rank: index + 1, standing: standing, isMe: standing.userId == myId)
                }
            }
        }
    }
}

private struct StandingRow: View {
    let rank: Int
    let standing: Standing
    let isMe: Bool
    @ScaledMetric(relativeTo: .body) private var rankWidth: CGFloat = 24

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(Palette.muted)
                .frame(width: rankWidth, alignment: .leading)
            Avatar(name: standing.name, size: AvatarSize.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(breakdown(spoken: false))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            Text("\(standing.points)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.text)
                .fixedSize()
        }
        .frame(minHeight: Space.hitTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rank). \(name), \(WeekFormat.points(standing.points)). \(breakdown(spoken: true))")
    }

    private var name: String {
        isMe ? "\(standing.name) · ты" : standing.name
    }

    /// "1 фото · 5 звёзд · ✍️ 1 · 😂 0 · 🫪 1 · 2 оценки другим"; spoken, the reactions are named.
    private func breakdown(spoken: Bool) -> String {
        var parts = ["\(standing.posts)\(nbsp)фото", WeekFormat.stars(standing.stars)]
        parts += ReactionKind.allCases.map { WeekFormat.mark($0, count(for: $0), spoken: spoken) }
        parts.append("\(WeekFormat.ratings(standing.given)) другим")
        return parts.joined(separator: spoken ? ", " : " · ")
    }

    private func count(for kind: ReactionKind) -> Int {
        switch kind {
        case .creative: return standing.creative
        case .funny: return standing.funny
        case .wild: return standing.wild
        }
    }
}

/// Closed weeks, newest first; each opens its results.
private struct HistorySection: View {
    let weeks: [WeekResults]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.header) {
            SectionHeader("Прошлые недели")
            Card {
                ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                    if index > 0 { WeekDivider() }
                    NavigationLink(value: week) {
                        HistoryRow(week: week)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let week: WeekResults

    var body: some View {
        HStack(spacing: 12) {
            Palette.raised
                .frame(width: 48, height: 48)
                .overlay {
                    if let url = week.bestPhoto?.imageUrl {
                        RemoteImage(url: url)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(week.rangeTitle)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
                Text(week.friendOfWeek.map { "Друг недели — \($0.name)" } ?? "Никто не набрал очков")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.faint)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Space.hitTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// How points and nominations are counted, collapsed by default.
private struct RulesCard: View {
    let deadline: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Card {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Каждая звезда на твоём фото — 1\(nbsp)очко")
                            .monospacedDigit()
                        Text("Каждая реакция \(marks) на твоём фото — 1\(nbsp)очко")
                            .monospacedDigit()
                            .accessibilityLabel("Каждая реакция \(spokenMarks) на твоём фото — 1\(nbsp)очко")
                        Text("Своё фото — 2\(nbsp)очка, в зачёт до 14\(nbsp)фото за неделю")
                            .monospacedDigit()
                        Text("Каждая твоя оценка или реакция друзьям — 1\(nbsp)очко")
                            .monospacedDigit()
                    }
                    WeekDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Друг недели — больше всех очков")
                        Text("Фото недели — больше всех звёзд")
                        ForEach(ReactionKind.allCases) { kind in
                            Text("\(kind.emoji) \(kind.nomination) — больше всех реакций «\(kind.title)»")
                                .accessibilityLabel("\(kind.nomination) — больше всех реакций «\(kind.title)»")
                        }
                        Text("Самый активный — больше всех очков за свои фото и оценки друзьям")
                    }
                    WeekDivider()
                    Text(closingNote)
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                }
                .font(.subheadline)
                .foregroundStyle(Palette.text)
                .padding(.top, 8)
            } label: {
                Text("Как считаются очки")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .frame(maxWidth: .infinity, minHeight: Space.hitTarget, alignment: .leading)
            }
            .tint(Palette.muted)
            .transaction { transaction in
                if reduceMotion { transaction.animation = nil }
            }
        }
    }

    private var marks: String {
        ReactionKind.allCases.map(\.emoji).joined(separator: " ")
    }

    /// The same reactions by name, for VoiceOver.
    private var spokenMarks: String {
        ReactionKind.allCases.map { "«\($0.title)»" }.joined(separator: ", ")
    }

    private var closingNote: String {
        let when = deadline.map { WeekDeadline.weekly($0) } ?? "в конце недели"
        return "Итоги подводятся автоматически \(when). Оценивать можно только фото текущей недели, свои — нельзя."
    }
}

/// Loading placeholder at the size of the lead card and the nomination rows.
private struct WeekSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            Card {
                SkeletonBlock(width: 120, height: 14)
                SkeletonBlock(width: 180, height: 22)
            }
            Card {
                ForEach(0..<4, id: \.self) { index in
                    if index > 0 { WeekDivider() }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBlock(width: 110, height: 12)
                            SkeletonBlock(width: 150, height: 16)
                        }
                        Spacer(minLength: 0)
                        SkeletonBlock(width: 64, height: 14)
                    }
                    .frame(minHeight: Space.hitTarget)
                }
            }
        }
        .appearsAfter()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Загружаю неделю…")
    }
}

/// A 1 pt line between the rows of a card.
private struct WeekDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Words

/// Numbers glued to their units with a non-breaking space: "11 очков", "3 реакции".
private enum WeekFormat {
    static func quantity(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        "\(n)\(nbsp)\(Russian.plural(n, one, few, many))"
    }

    static func points(_ n: Int) -> String { quantity(n, "очко", "очка", "очков") }
    static func reactions(_ n: Int) -> String { quantity(n, "реакция", "реакции", "реакций") }
    static func stars(_ n: Int) -> String { quantity(n, "звезда", "звезды", "звёзд") }
    static func ratings(_ n: Int) -> String { quantity(n, "оценка", "оценки", "оценок") }

    /// "✍️ 3": the reaction's mark is the unit. Spoken it is "Креатив 3":
    /// VoiceOver has no name for 🫪 before iOS 26.4.
    static func mark(_ kind: ReactionKind, _ n: Int, spoken: Bool = false) -> String {
        spoken ? "\(kind.title) \(n)" : "\(kind.emoji)\(nbsp)\(n)"
    }
}

/// The week's end in words: "в воскресенье в 21:00", "завтра в 21:00", "через 2 дня".
private enum WeekDeadline {
    /// The weekday with its preposition, indexed by `Calendar` weekday (1 is Sunday).
    private static let weekdays = ["в воскресенье", "в понедельник", "во вторник", "в среду", "в четверг", "в пятницу", "в субботу"]

    /// "в воскресенье в 21:00"
    static func weekly(_ date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        return "\(weekdays[(weekday + 6) % 7]) в \(time(date))"
    }

    /// "сегодня в 21:00", "завтра в 21:00", otherwise "в воскресенье в 21:00"
    static func upcoming(_ date: Date, from now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return "сегодня в \(time(date))"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "завтра в \(time(date))"
        }
        return weekly(date)
    }

    /// "через 2 дня", "через 5 часов", "через 1 минуту"; nil once the date has passed.
    static func remaining(until date: Date, from now: Date) -> String? {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 {
            return "через \(WeekFormat.quantity(minutes, "минуту", "минуты", "минут"))"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "через \(WeekFormat.quantity(hours, "час", "часа", "часов"))"
        }
        return "через \(WeekFormat.quantity(hours / 24, "день", "дня", "дней"))"
    }

    private static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(.ru))
    }
}
