import SwiftUI

/// The current week: how long is left and that everything stays a secret until then,
/// then past weeks and how the winners are chosen. Ratings are blind: no points,
/// no table, no counts. A closed week names only its winners.
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

    /// The first block: the week is a secret until it closes, or why there is nothing yet.
    @ViewBuilder
    private var status: some View {
        if let failure {
            InlineError(message: failureMessage(failure)) {
                Task { await model.refreshWeek() }
            }
        }
        if model.friends.isEmpty {
            // Winners are chosen among you and your friends: alone there is no one to compare.
            EmptyState(
                text: "Победителей выбирают среди друзей — найди их во вкладке «Друзья».",
                actionTitle: "Найти друзей",
                action: { model.selectedTab = .friends }
            )
        } else if let week = model.currentWeek {
            if week.photoCount == 0 {
                EmptyState(
                    text: "На этой неделе ещё нет фото — выложи первое.",
                    actionTitle: "Сделать фото",
                    action: { model.selectedTab = .camera }
                )
            } else {
                SecretCard(photoCount: week.photoCount ?? 0, deadline: endDate)
            }
        } else if failure == nil {
            WeekSkeleton()
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

/// A finished week: its winners only. From past weeks and from the weekly results push.
struct WeekResultsView: View {
    let results: WeekResults

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                VStack(alignment: .leading, spacing: Space.gap) {
                    ScreenTitle(title: "Итоги недели", subtitle: results.rangeTitle)
                    if results.photoCount == 0 {
                        EmptyState(text: "На этой неделе никто не выложил фото.")
                    } else {
                        LeadCard(title: "Друг недели", nominee: results.friendOfWeek, emptyText: "Друга недели нет — неделя вышла тихой.")
                    }
                }
                if results.photoCount != 0 {
                    if let best = results.bestPhoto {
                        PrizePhotoSection(title: "Пост недели", photo: best)
                    }
                    if let days = results.postsOfDay, !days.isEmpty {
                        PostsOfDaySection(days: days)
                    }
                    PostNominationsSection(results: results)
                    FriendNominationsSection(results: results)
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

/// While the week runs there is nothing to show: no leader, no counts. Only when
/// the winners will be named, and how many photos are in play.
private struct SecretCard: View {
    let photoCount: Int
    let deadline: Date?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label("Пока секрет", systemImage: "eye.slash")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                Text(headline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Звёзды и реакции не видит никто — ни ты, ни друзья, ни автор фото. В итогах будут только победители: друг недели, пост недели, посты дня и номинации.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(photoCount)\(nbsp)фото у тебя и друзей на этой неделе")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        guard let deadline else { return "Победителей назовём в конце недели" }
        return "Победителей назовём \(WeekDeadline.weekly(deadline))"
    }
}

/// The friend of the week: the name, never a score.
private struct LeadCard: View {
    let title: String
    let nominee: Nominee?
    let emptyText: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                if let nominee {
                    HStack(spacing: 12) {
                        Avatar(name: nominee.name, size: AvatarSize.regular)
                        Text(nominee.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                            .lineLimit(2)
                    }
                } else {
                    Text(emptyText)
                        .font(.body)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A winning post: the picture, its author and caption. No counts.
private struct PrizePhotoSection: View {
    let title: String
    let photo: BestPhoto

    var body: some View {
        VStack(alignment: .leading, spacing: Space.header) {
            SectionHeader(title)
            SquarePhoto(url: photo.imageUrl)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title), автор — \(photo.authorName)")
                .accessibilityAddTraits(.isImage)
            HStack(alignment: .top, spacing: 10) {
                Avatar(name: photo.authorName, size: AvatarSize.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(photo.authorName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    if let caption = photo.caption, !caption.isBlank {
                        Text("«\(caption)»")
                            .font(.subheadline)
                            .italic()
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(minHeight: AvatarSize.small)
            .accessibilityElement(children: .combine)
        }
    }
}

/// «Посты дня»: the best post of each day, in a row that scrolls sideways.
private struct PostsOfDaySection: View {
    let days: [DayPost]
    @ScaledMetric(relativeTo: .body) private var tile: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: Space.header) {
            SectionHeader("Посты дня")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(days) { day in
                        VStack(alignment: .leading, spacing: 6) {
                            SquarePhoto(url: day.photo.imageUrl, cornerRadius: Radius.card)
                            Text(day.weekday)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.text)
                                .lineLimit(1)
                            Text(day.photo.authorName)
                                .font(.footnote)
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                        }
                        .frame(width: tile, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(day.weekday), пост дня — \(day.photo.authorName)")
                        .accessibilityAddTraits(.isImage)
                    }
                }
                .padding(.horizontal, Space.margin)
            }
            // The row runs to the screen edges while its first tile lines up with the text.
            .padding(.horizontal, -Space.margin)
        }
    }
}

private extension DayPost {
    /// "Среда" for "2026-10-14". Gregorian on purpose: the server's dates are.
    var weekday: String {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        let calendar = Calendar(identifier: .gregorian)
        guard parts.count == 3,
              let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        else { return date }
        let name = day.formatted(.dateTime.weekday(.wide).locale(.ru))
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

/// The most ✍️ / 😂 / 🫪 posts: a thumbnail, the nomination and the author.
private struct PostNominationsSection: View {
    let results: WeekResults

    var body: some View {
        VStack(alignment: .leading, spacing: Space.header) {
            SectionHeader("Лучшие посты")
            Card {
                ForEach(Array(ReactionKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { WeekDivider() }
                    PostNominationRow(kind: kind, photo: post(for: kind))
                }
            }
        }
    }

    private func post(for kind: ReactionKind) -> BestPhoto? {
        switch kind {
        case .creative: return results.mostCreativePost
        case .funny: return results.mostFunnyPost
        case .wild: return results.mostWildPost
        }
    }
}

private struct PostNominationRow: View {
    let kind: ReactionKind
    let photo: BestPhoto?

    var body: some View {
        HStack(spacing: 12) {
            Palette.raised
                .frame(width: 48, height: 48)
                .overlay {
                    if let url = photo?.imageUrl {
                        RemoteImage(url: url)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .accessibilityHidden(true)
            WinnerLabel(mark: kind.emoji, title: "\(kind.nomination) пост", name: photo?.authorName)
            Spacer(minLength: 0)
        }
        .frame(minHeight: Space.hitTarget)
        .accessibilityElement(children: .combine)
    }
}

/// The friends who won: names only. Who was picked least in «Кто лучше?» is never told.
private struct FriendNominationsSection: View {
    let results: WeekResults

    var body: some View {
        VStack(alignment: .leading, spacing: Space.header) {
            SectionHeader("Номинации")
            // The friend of the week leads the screen in its own card, so it is not repeated here.
            Card {
                if let favorite = results.favoriteFriend {
                    NominationRow(title: "Самый любимый друг", name: favorite.name)
                    WeekDivider()
                }
                ForEach(ReactionKind.allCases) { kind in
                    NominationRow(mark: kind.emoji, title: "\(kind.nomination) друг", name: nominee(for: kind)?.name)
                    WeekDivider()
                }
                NominationRow(title: "Самый активный", name: results.mostActive?.name)
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
    var mark: String? = nil
    let title: String
    let name: String?

    var body: some View {
        WinnerLabel(mark: mark, title: title, name: name)
            .frame(maxWidth: .infinity, minHeight: Space.hitTarget, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

/// A nomination over its winner; "—" when nobody won it.
private struct WinnerLabel: View {
    /// The reaction's emoji, shown before the title but not read by VoiceOver.
    var mark: String?
    let title: String
    let name: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(mark.map { "\($0) \(title)" } ?? title)
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .accessibilityLabel(title)
            if let name {
                Text(name)
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
                Text(week.friendOfWeek.map { "Друг недели — \($0.name)" } ?? "Без друга недели")
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

/// How winners are chosen, collapsed by default. Says plainly that nothing is counted out loud.
private struct RulesCard: View {
    let deadline: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Card {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Звёзды и реакции тайные: их не видит никто, даже автор фото. Ни очков, ни таблицы — в итогах только победители.")
                        .fixedSize(horizontal: false, vertical: true)
                    WeekDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Пост недели — больше всех звёзд")
                        Text("Пост дня — больше всех звёзд за день")
                        ForEach(ReactionKind.allCases) { kind in
                            Text("\(kind.emoji) \(kind.nomination) пост — больше всех реакций «\(kind.title)»")
                                .accessibilityLabel("\(kind.nomination) пост — больше всех реакций «\(kind.title)»")
                        }
                    }
                    WeekDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Друг недели — больше всех звёзд и реакций на своих фото; свои фото и оценки друзьям тоже идут в зачёт")
                        ForEach(ReactionKind.allCases) { kind in
                            Text("\(kind.emoji) \(kind.nomination) друг — больше всех реакций «\(kind.title)» на своих фото")
                                .accessibilityLabel("\(kind.nomination) друг — больше всех реакций «\(kind.title)» на своих фото")
                        }
                        Text("Самый любимый друг — того чаще всех выбирают в «Кто лучше?». Кого реже — не скажем")
                        Text("Самый активный — больше всех своих фото и оценок друзьям")
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
                Text("Как выбираем победителей")
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

    private var closingNote: String {
        let when = deadline.map { WeekDeadline.weekly($0) } ?? "в конце недели"
        return "Итоги подводятся автоматически \(when). Оценивать можно только фото текущей недели, свои — нельзя."
    }
}

/// Loading placeholder at the size of the secret card.
private struct WeekSkeleton: View {
    var body: some View {
        Card {
            SkeletonBlock(width: 110, height: 14)
            SkeletonBlock(width: 240, height: 22)
            SkeletonBlock(height: 14)
            SkeletonBlock(width: 200, height: 14)
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

/// Numbers glued to their units with a non-breaking space: "2 дня", "5 часов".
private enum WeekFormat {
    static func quantity(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        "\(n)\(nbsp)\(Russian.plural(n, one, few, many))"
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
