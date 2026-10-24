import SwiftUI

/// Friends' photos, newest first, grouped by week. The finding is how many still wait for
/// your rating and how many are still locked.
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
        if let duel = model.todayDuel, duel.choice == nil {
            DuelPrompt(duel: duel)
                .padding(.horizontal, Space.margin)
        }
        if model.friends.isEmpty {
            // Without friends the feed holds only your own photos (a new account starts
            // with one), so this shows above them, not only when the feed is empty.
            EmptyState(
                text: "Пока у тебя нет друзей — найди их по юзернейму.",
                actionTitle: "Найти друзей",
                action: { model.selectedTab = .friends }
            )
            .padding(.horizontal, Space.margin)
        }
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
                if !model.friends.isEmpty {
                    EmptyState(
                        text: "Пока никто ничего не выложил — сделай первое фото.",
                        actionTitle: "Открыть камеру",
                        action: { model.selectedTab = .camera }
                    )
                    .padding(.horizontal, Space.margin)
                }
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
                        if photo.locked {
                            LockedPhotoCard(photo: photo)
                        } else {
                            PhotoCard(photo: photo)
                        }
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

    /// "3 фото ждут твоей оценки · 2 закрыты" (only the parts that aren't zero),
    /// or that this week's friends' photos are all rated.
    private var finding: String? {
        let unrated = model.unratedCount
        let locked = model.lockedCount
        var parts: [String] = []
        if unrated > 0 {
            let waiting = Russian.plural(unrated, "фото ждёт", "фото ждут", "фото ждут")
            parts.append("\(unrated)\(nbsp)\(waiting) твоей оценки")
        }
        if locked > 0 {
            let closed = Russian.plural(locked, "закрыто", "закрыты", "закрыты")
            // On its own the number needs its noun: "2 фото закрыты".
            parts.append(unrated > 0 ? "\(locked)\(nbsp)\(closed)" : "\(locked)\(nbsp)фото \(closed)")
        }
        if !parts.isEmpty {
            return parts.joined(separator: " · ")
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

/// One photo: who posted it and when, the photo with its caption, and your rating.
/// Ratings are blind: nobody sees totals or who gave what, not even the author.
struct PhotoCard: View {
    @Environment(AppModel.self) private var model
    let photo: Photo
    @State private var confirmDelete = false

    private var isMine: Bool { photo.authorId == model.myId }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            author

            SquarePhoto(url: photo.imageUrl)
                .overlay {
                    // Open photos always carry a picture; this only guards a bad response.
                    if photo.imageUrl == nil {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(Palette.faint)
                    }
                }
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

            if isMine {
                SecretRatingNote()
            } else {
                RatingBar(photo: photo)
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
            PhotoByline(photo: photo, isMine: isMine)
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

    /// "Фото, подпись «…»" for VoiceOver.
    private var photoSpoken: String {
        if photo.imageUrl == nil { return "Фото не загрузилось" }
        guard let caption = photo.caption, !caption.isBlank else { return "Фото" }
        return "Фото, подпись «\(caption)»"
    }
}

/// Under your own photo instead of stars: friends rate it, but the numbers stay
/// hidden from everyone. Only the winners are named when the week closes.
private struct SecretRatingNote: View {
    var body: some View {
        Label {
            Text("Оценки друзей — секрет. Победителей объявим в\(nbsp)воскресенье")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "eye.slash")
        }
        .font(.footnote)
        .foregroundStyle(Palette.muted)
        .frame(minHeight: Space.hitTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A friend's photo you haven't opened yet: who posted it, when, and how to open it.
/// Posting your own photo opens one more from each friend. Nothing to rate here.
private struct LockedPhotoCard: View {
    @Environment(AppModel.self) private var model
    let photo: Photo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // VoiceOver hears who and when in the tile's own label.
            PhotoByline(photo: photo, isMine: false)
                .accessibilityHidden(true)

            ZStack {
                // At least square, like an open photo; taller if large text needs the room.
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                VStack(spacing: Space.gap) {
                    VStack(spacing: 8) {
                        Image(systemName: "lock")
                            .font(.title)
                            .foregroundStyle(Palette.muted)
                        Text("Закрыто")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.text)
                        Text("Выложи своё фото — и откроется ещё одно")
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spoken)

                    Button("Открыть камеру") {
                        model.selectedTab = .camera
                    }
                    .buttonStyle(LocketButtonStyle(.secondary, fullWidth: false))
                }
                .padding(Space.cardPadding)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
        }
        .padding(.horizontal, Space.margin)
    }

    /// "Закрытое фото от барсук, 5 минут назад. Выложи своё, чтобы открыть"
    private var spoken: String {
        "Закрытое фото от \(photo.authorName), \(photo.postedAgo). Выложи своё, чтобы открыть"
    }
}

/// Avatar, name and how long ago: the top row of every card.
private struct PhotoByline: View {
    let photo: Photo
    let isMine: Bool

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: photo.authorName, size: AvatarSize.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(isMine ? "Ты" : photo.authorName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(photo.postedAgo)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Palette.muted)
            }
        }
    }
}

private extension Photo {
    /// "5 минут назад", with the number kept next to its unit.
    var postedAgo: String {
        date.formatted(.relative(presentation: .named).locale(.ru))
            .replacingOccurrences(of: #"(\d) "#, with: "$1\(nbsp)", options: .regularExpression)
    }
}

/// Stars 1–3 and the reactions under a friend's photo. Your choice is yellow, filled
/// and marked selected. No counts: you see only what you gave. Closed weeks are read-only.
struct RatingBar: View {
    @Environment(AppModel.self) private var model
    let photo: Photo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(1...Stars.max, id: \.self) { value in
                    star(value)
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

    private var isClosed: Bool { !photo.canReact }

    private func star(_ value: Int) -> some View {
        let lit = value <= photo.myStars
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
        .accessibilityAddTraits(value == photo.myStars ? .isSelected : [])
        .accessibilityRemoveTraits(photo.canReact ? [] : .isButton)
    }

    private var reactions: some View {
        ForEach(ReactionKind.allCases) { kind in
            chip(kind)
        }
    }

    private func chip(_ kind: ReactionKind) -> some View {
        let active = photo.mine.contains(kind)
        return Button {
            guard photo.canReact else { return }
            Task { await model.toggle(kind, on: photo) }
        } label: {
            Text(kind.emoji)
                .font(.title3)
                .padding(.horizontal, 14)
            .frame(minWidth: 56, minHeight: Space.hitTarget)
            .background(active ? Palette.accentTint : Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(active ? Palette.accent : Color.clear, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(photo.canReact)
        .accessibilityLabel(kind.title)
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

/// Today's «Кто лучше?» when it wasn't answered from the lock screen.
private struct DuelPrompt: View {
    @Environment(AppModel.self) private var model
    let duel: Duel
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                Text("Кто лучше?")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Выбери одного — кого не выбрал, никто не узнает")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DuelChoiceView(duel: duel, busy: busy) { pick in
                Task { await choose(pick) }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Palette.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func choose(_ pick: DuelPick) async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await model.chooseDuel(pick)
        } catch is CancellationError {
        } catch {
            self.error = "Не сохранилось: \(error.localizedDescription)"
        }
    }
}
