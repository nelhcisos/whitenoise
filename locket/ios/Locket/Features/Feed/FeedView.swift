import SwiftUI

struct FeedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 32) {
                        ForEach(sections, id: \.weekId) { section in
                            Text(section.title)
                                .font(.title3.bold())
                                .padding(.horizontal, 16)
                            ForEach(section.photos) { photo in
                                PhotoCard(photo: photo)
                                    .id(photo.id)
                                    .task { await model.loadMoreIfNeeded(after: photo) }
                            }
                        }
                        if model.isLoadingMore {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .refreshable { await model.refreshFeed() }
                .overlay {
                    if model.feed.isEmpty {
                        ContentUnavailableView(
                            "Пока пусто",
                            systemImage: "camera.viewfinder",
                            description: Text("Сделай фото — друзья получат его прямо на экран блокировки и поставят ⭐ и ✍️ 😂 🫪")
                        )
                    }
                }
                .onAppear { scrollToFocus(proxy) }
                .onChange(of: model.focusPhotoId) { scrollToFocus(proxy) }
                .onChange(of: model.feed.count) { scrollToFocus(proxy) }
            }
            .navigationTitle("Лента")
        }
    }

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
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(.ru)
        for index in result.indices {
            let section = result[index]
            if section.weekId == model.me?.week.id {
                result[index].title = "Эта неделя"
            } else if let newest = section.photos.first, let oldest = section.photos.last {
                let from = oldest.date.formatted(style)
                let to = newest.date.formatted(style)
                result[index].title = from == to ? from : "\(from) – \(to)"
            }
        }
        return result
    }

    private func scrollToFocus(_ proxy: ScrollViewProxy) {
        guard let id = model.focusPhotoId, model.feed.contains(where: { $0.id == id }) else { return }
        withAnimation { proxy.scrollTo(id, anchor: .top) }
        model.focusPhotoId = nil
    }
}

struct PhotoCard: View {
    @Environment(AppModel.self) private var model
    let photo: Photo
    @State private var confirmDelete = false

    private var isMine: Bool { photo.authorId == model.myId }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Avatar(name: photo.authorName, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(isMine ? "Ты" : photo.authorName).font(.headline)
                    Text(photo.date, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isMine {
                    Menu {
                        Button("Удалить фото", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                    }
                }
            }

            SquarePhoto(url: photo.imageUrl)
                .overlay(alignment: .bottom) {
                    if let caption = photo.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Color.black.opacity(0.5), in: Capsule())
                            .padding(16)
                    }
                }

            RatingBar(photo: photo, isMine: isMine)

            if !photo.reactors.isEmpty || !photo.raters.isEmpty {
                Text(reactorsLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .confirmationDialog("Удалить это фото?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await model.delete(photo) } }
        }
    }

    /// "Петя ⭐⭐⭐ 😂 · Оля ⭐ ✍️"
    private var reactorsLine: String {
        var order: [String] = []
        var names: [String: String] = [:]
        var stars: [String: Int] = [:]
        var kinds: [String: Set<ReactionKind>] = [:]
        func note(_ userId: String, _ name: String) {
            if names[userId] == nil { order.append(userId) }
            names[userId] = name
        }
        for rater in photo.raters {
            note(rater.userId, rater.name)
            stars[rater.userId] = rater.stars
        }
        for reactor in photo.reactors {
            note(reactor.userId, reactor.name)
            kinds[reactor.userId, default: []].insert(reactor.kind)
        }
        return order.map { id in
            let given = String(repeating: "⭐", count: stars[id] ?? 0)
            let emojis = ReactionKind.allCases.filter { kinds[id]?.contains($0) == true }.map(\.emoji).joined()
            return [names[id] ?? "", given, emojis].filter { !$0.isEmpty }.joined(separator: " ")
        }
        .joined(separator: " · ")
    }
}

/// ⭐ 1–3 on the left, ✍️ 😂 🫪 toggles on the right. Own photos and closed weeks are read-only.
struct RatingBar: View {
    @Environment(AppModel.self) private var model
    let photo: Photo
    let isMine: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(1...Stars.max, id: \.self) { value in
                    Button {
                        Task { await model.setStars(value, on: photo) }
                    } label: {
                        Image(systemName: value <= shownStars ? "star.fill" : "star")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(value <= shownStars ? Color.locketYellow : Color.white.opacity(0.35))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(photo.canReact)
                    .accessibilityLabel("\(value) из \(Stars.max)")
                }
                Text(starsSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                ForEach(ReactionKind.allCases) { kind in
                    let active = photo.mine.contains(kind)
                    let count = photo.counts[kind]
                    Button {
                        Task { await model.toggle(kind, on: photo) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(kind.emoji).font(.title3)
                            if count > 0 {
                                Text("\(count)").font(.subheadline.weight(.bold)).monospacedDigit()
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 56, minHeight: 44)
                        .background(active ? Color.locketYellow.opacity(0.22) : Color.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(active ? Color.locketYellow : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(photo.canReact)
                    .accessibilityLabel("\(kind.title): \(count)")
                }
                Spacer(minLength: 0)
                if !photo.canReact && !isMine {
                    Label("неделя закрыта", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: photo.mine)
        .sensoryFeedback(.selection, trigger: photo.myStars)
    }

    /// Your own photo shows its average; a friend's shows what you gave.
    private var shownStars: Int {
        isMine ? Int(photo.stars.average.rounded()) : photo.myStars
    }

    private var starsSummary: String {
        guard photo.stars.count > 0 else { return isMine ? "ещё нет оценок" : "" }
        let average = photo.stars.average.formatted(.number.precision(.fractionLength(0...1)).locale(.ru))
        return "\(average) · \(photo.stars.count) \(Russian.plural(photo.stars.count, "оценка", "оценки", "оценок"))"
    }
}
