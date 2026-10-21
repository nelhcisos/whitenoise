import SwiftUI

/// Friends' photos, newest first, grouped by week. The finding is how many still wait for your rating.
struct FeedView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.section) {
                        header
                        content
                    }
                    .padding(.top, Space.gap)
                    .padding(.bottom, Space.section)
                }
                .refreshable { await model.refreshFeed() }
                .safeAreaInset(edge: .top, spacing: 0) {
                    // Keeps scrolled photos from showing under the status bar.
                    Color.clear
                        .frame(height: 0)
                        .background(Palette.ground, ignoresSafeAreaEdges: .top)
                }
                .onAppear { scrollToFocus(proxy) }
                .onChange(of: model.focusPhotoId) { scrollToFocus(proxy) }
                .onChange(of: model.feed.count) { scrollToFocus(proxy) }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            ScreenTitle(title: "Лента", subtitle: finding)
            if case .failed(let message) = model.feedState {
                // Photos already loaded stay below the error.
                InlineError(message: "Не удалось загрузить ленту. \(message)") {
                    Task { await model.refreshFeed() }
                }
            }
        }
        .padding(.horizontal, Space.margin)
    }

    @ViewBuilder
    private var content: some View {
        if model.feed.isEmpty {
            switch model.feedState {
            case .idle, .loading:
                VStack(alignment: .leading, spacing: Space.section) {
                    PhotoCardSkeleton()
                    PhotoCardSkeleton()
                }
                .appearsAfter()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Загружаю ленту…")
            case .loaded:
                EmptyState(
                    text: "Пока никто ничего не выложил — сделай первое фото.",
                    actionTitle: "Открыть камеру",
                    action: { model.selectedTab = .camera }
                )
                .padding(.horizontal, Space.margin)
            case .failed:
                EmptyView()
            }
        } else {
            ForEach(sections, id: \.weekId) { section in
                ForEach(section.photos) { photo in
                    VStack(alignment: .leading, spacing: Space.header) {
                        if photo.id == section.photos.first?.id {
                            SectionHeader(section.title)
                                .padding(.horizontal, Space.margin)
                        }
                        PhotoCard(photo: photo)
                    }
                    .id(photo.id)
                    .task { await model.loadMoreIfNeeded(after: photo) }
                }
            }
            if let message = model.loadMoreError {
                InlineError(message: "Не удалось загрузить старые фото. \(message)") {
                    Task { await model.retryLoadMore() }
                }
                .padding(.horizontal, Space.margin)
            } else if model.isLoadingMore {
                PhotoCardSkeleton()
                    .appearsAfter()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Загружаю ещё фото…")
            }
        }
    }

    /// "3 фото ждут твоей оценки", or that this week's friends' photos are all rated.
    private var finding: String? {
        let unrated = model.unratedCount
        if unrated > 0 {
            let waiting = Russian.plural(unrated, "фото ждёт", "фото ждут", "фото ждут")
            return "\(unrated)\(nbsp)\(waiting) твоей оценки"
        }
        // Only friends' photos of this week can be rated.
        if model.feed.contains(where: { $0.canReact }) {
            return "Ты оценил все фото этой недели"
        }
        return nil
    }

    // MARK: - Sections

    private struct FeedSection {
        let weekId: String
        var title: String
        var photos: [Photo]
    }

    private var sections: [FeedSection] {
        var result: [FeedSection] = []
        for photo in model.feed {
            if result.last?.weekId == photo.weekId {
                result[result.count - 1].photos.append(photo)
            } else {
                result.append(FeedSection(weekId: photo.weekId, title: "", photos: [photo]))
            }
        }
        for index in result.indices {
            let section = result[index]
            if section.weekId == model.me?.week.id {
                result[index].title = "Эта неделя"
            } else if let newest = section.photos.first, let oldest = section.photos.last {
                let from = oldest.date.dayMonth
                let to = newest.date.dayMonth
                result[index].title = from == to ? from : "\(from) – \(to)"
            }
        }
        return result
    }

    private func scrollToFocus(_ proxy: ScrollViewProxy) {
        guard let id = model.focusPhotoId, model.feed.contains(where: { $0.id == id }) else { return }
        withAnimation(reduceMotion ? nil : .default) {
            proxy.scrollTo(id, anchor: .top)
        }
        model.focusPhotoId = nil
    }
}

/// One photo: who posted it and when, the photo with its caption, the rating, who rated it.
struct PhotoCard: View {
    @Environment(AppModel.self) private var model
    let photo: Photo
    @State private var confirmDelete = false

    private var isMine: Bool { photo.authorId == model.myId }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            author

            SquarePhoto(url: photo.imageUrl)
                .overlay(alignment: .bottom) {
                    if let caption = photo.caption, !caption.isBlank {
                        Text(caption)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.text)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Palette.scrim, in: Capsule())
                            .padding(Space.gap)
                    }
                }
                // One VoiceOver stop for the photo and its caption.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(photoSpoken)
                .accessibilityAddTraits(.isImage)

            RatingBar(photo: photo, isMine: isMine)

            if !photo.reactors.isEmpty || !photo.raters.isEmpty {
                Text(reactorsLine)
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(reactorsSpoken)
            }
        }
        .padding(.horizontal, Space.margin)
        .confirmationDialog("Удалить это фото?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить фото", role: .destructive) {
                Task { await model.delete(photo) }
            }
        } message: {
            Text("Друзья больше его не увидят, оценки за него пропадут.")
        }
    }

    private var author: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Avatar(name: photo.authorName, size: AvatarSize.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isMine ? "Ты" : photo.authorName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text(postedAgo)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            if isMine {
                Menu {
                    Button("Удалить фото…", systemImage: "trash", role: .destructive) {
                        confirmDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: Space.hitTarget, height: Space.hitTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Ещё")
            }
        }
    }

    /// "5 минут назад", with the number kept next to its unit.
    private var postedAgo: String {
        photo.date.formatted(.relative(presentation: .named).locale(.ru))
            .replacingOccurrences(of: #"(\d) "#, with: "$1\(nbsp)", options: .regularExpression)
    }

    /// "Фото, подпись «…»" for VoiceOver.
    private var photoSpoken: String {
        guard let caption = photo.caption, !caption.isBlank else { return "Фото" }
        return "Фото, подпись «\(caption)»"
    }

    /// One person's rating of this photo.
    private struct Given {
        let name: String
        var stars = 0
        var kinds: Set<ReactionKind> = []
    }

    /// Everyone who rated, in the order they first did.
    private var given: [Given] {
        var order: [String] = []
        var byUser: [String: Given] = [:]
        func note(_ userId: String, _ name: String) {
            if byUser[userId] == nil {
                order.append(userId)
                byUser[userId] = Given(name: name)
            }
        }
        for rater in photo.raters {
            note(rater.userId, rater.name)
            byUser[rater.userId]?.stars = rater.stars
        }
        for reactor in photo.reactors {
            note(reactor.userId, reactor.name)
            byUser[reactor.userId]?.kinds.insert(reactor.kind)
        }
        return order.compactMap { byUser[$0] }
    }

    /// "Петя ★★★ 😂 · Оля ★ ✍️"
    private var reactorsLine: String {
        given.map { entry -> String in
            let stars = String(repeating: "★", count: entry.stars)
            let marks = ReactionKind.allCases.filter { entry.kinds.contains($0) }.map(\.emoji).joined()
            return [entry.name, stars, marks].filter { !$0.isEmpty }.joined(separator: " ")
        }
        .joined(separator: " · ")
    }

    /// The same line for VoiceOver: "Петя: 3 из 3, Смешно. Оля: 1 из 3, Креатив".
    private var reactorsSpoken: String {
        given.map { entry -> String in
            var parts: [String] = []
            if entry.stars > 0 { parts.append("\(entry.stars) из \(Stars.max)") }
            parts += ReactionKind.allCases.filter { entry.kinds.contains($0) }.map(\.title)
            return "\(entry.name): \(parts.joined(separator: ", "))"
        }
        .joined(separator: ". ")
    }
}

/// Stars 1–3 and the reactions under a photo. Your choice is yellow, filled and marked
/// selected; your own photo shows its average. Own photos and closed weeks are read-only.
struct RatingBar: View {
    @Environment(AppModel.self) private var model
    let photo: Photo
    let isMine: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(1...Stars.max, id: \.self) { value in
                    star(value)
                }
                if let starsSummary {
                    Text(starsSummary)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                        .padding(.leading, 8)
                }
                Spacer(minLength: 0)
            }

            if isClosed {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        reactions
                        Spacer(minLength: 8)
                        closedNote
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) { reactions }
                        closedNote
                    }
                }
            } else {
                HStack(spacing: 8) { reactions }
            }
        }
        .sensoryFeedback(.selection, trigger: photo.mine)
        .sensoryFeedback(.selection, trigger: photo.myStars)
    }

    private var isClosed: Bool { !photo.canReact && !isMine }

    /// Your own photo shows its average; a friend's shows what you gave.
    private var shownStars: Int {
        isMine ? Int(photo.stars.average.rounded()) : photo.myStars
    }

    /// "2,5 · 4 оценки"; nothing for a friend's photo nobody has rated yet.
    private var starsSummary: String? {
        guard photo.stars.count > 0 else { return isMine ? "ещё нет оценок" : nil }
        let average = photo.stars.average.formatted(.number.precision(.fractionLength(0...1)).locale(.ru))
        let count = photo.stars.count
        return "\(average) · \(count)\(nbsp)\(Russian.plural(count, "оценка", "оценки", "оценок"))"
    }

    private func star(_ value: Int) -> some View {
        let lit = value <= shownStars
        return Button {
            guard photo.canReact else { return }
            Task { await model.setStars(value, on: photo) }
        } label: {
            Image(systemName: lit ? "star.fill" : "star")
                .font(.title3.weight(.semibold))
                .foregroundStyle(lit ? Palette.accent : Palette.faint)
                .frame(width: Space.hitTarget, height: Space.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(photo.canReact)
        .accessibilityLabel("\(value) из \(Stars.max)")
        // Selected is your own pick only, not every lit star.
        .accessibilityAddTraits(!isMine && value == photo.myStars ? .isSelected : [])
        .accessibilityRemoveTraits(photo.canReact ? [] : .isButton)
        // On your photo the stars draw the average, which the summary next to them reads out.
        .accessibilityHidden(isMine)
    }

    private var reactions: some View {
        ForEach(ReactionKind.allCases) { kind in
            chip(kind)
        }
    }

    private func chip(_ kind: ReactionKind) -> some View {
        let active = photo.mine.contains(kind)
        let count = photo.counts[kind]
        return Button {
            guard photo.canReact else { return }
            Task { await model.toggle(kind, on: photo) }
        } label: {
            HStack(spacing: 6) {
                Text(kind.emoji)
                    .font(.title3)
                if count > 0 {
                    Text("\(count)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.text)
                }
            }
            .padding(.horizontal, 14)
            .frame(minWidth: 56, minHeight: Space.hitTarget)
            .background(active ? Palette.accentTint : Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(active ? Palette.accent : Color.clear, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(photo.canReact)
        .accessibilityLabel(kind.title)
        .accessibilityValue(String(count))
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityRemoveTraits(photo.canReact ? [] : .isButton)
    }

    private var closedNote: some View {
        Label("Неделя закрыта", systemImage: "lock")
            .font(.footnote)
            .foregroundStyle(Palette.faint)
    }
}

/// A photo card's shape while the feed loads: the same sizes in flat raised blocks.
private struct PhotoCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SkeletonBlock(width: AvatarSize.small, height: AvatarSize.small, cornerRadius: AvatarSize.small / 2)
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBlock(width: 120, height: 14)
                    SkeletonBlock(width: 72, height: 10)
                }
            }
            .frame(minHeight: Space.hitTarget)

            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GeometryReader { geometry in
                        SkeletonBlock(height: geometry.size.height, cornerRadius: Radius.photo)
                    }
                }

            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(width: 132, height: 20)
                    .frame(height: Space.hitTarget)
                HStack(spacing: 8) {
                    ForEach(0..<ReactionKind.allCases.count, id: \.self) { _ in
                        SkeletonBlock(width: 56, height: Space.hitTarget, cornerRadius: Space.hitTarget / 2)
                    }
                }
            }
        }
        .padding(.horizontal, Space.margin)
    }
}
