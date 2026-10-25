import SwiftUI
import UserNotifications

/// Friends, found by username: your own username to share and your wishlist, search,
/// requests, the friends themselves (each with their wishlist), notifications and, last,
/// the way out.
struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var notificationStatus: UNAuthorizationStatus?

    // Search
    @State private var query = ""
    /// Bumped by Retry so the same query runs again.
    @State private var searchAttempt = 0
    @State private var searchPhase: SearchPhase = .idle
    @State private var results: [UserSearchResult] = []

    // Friend actions, keyed by the other person's id
    @State private var busy: [String: FriendAction] = [:]
    /// The last failed action, shown under that person's row.
    @State private var rowErrors: [String: String] = [:]
    @State private var friendToRemove: FriendEntry?

    @State private var pickingBirthday = false

    @State private var confirmSignOut = false
    @State private var signingOut = false

    private enum SearchPhase: Equatable {
        case idle, searching, done, failed(String)
    }

    private struct SearchKey: Equatable {
        let term: String
        let attempt: Int
    }

    private enum FriendAction {
        case add, accept, decline, cancel, remove

        /// The first half of the inline error; the server's reason follows.
        var failure: String {
            switch self {
            case .add: return "Заявка не отправилась."
            case .accept: return "Не удалось принять заявку."
            case .decline: return "Не удалось отклонить заявку."
            case .cancel: return "Не удалось отменить заявку."
            case .remove: return "Не удалось удалить из друзей."
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                ScreenTitle(title: "Друзья", subtitle: finding)
                if let username = model.username {
                    usernameCard(username)
                }
                searchSection
                socialSections
                notifications
                exitButton
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.gap)
            .padding(.bottom, Space.section)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.refreshSocial() }
        .background(Palette.ground)
        .safeAreaInset(edge: .top, spacing: 0) {
            // Keeps scrolled content from showing under the status bar.
            Color.clear
                .frame(height: 0)
                .background(Palette.ground, ignoresSafeAreaEdges: .top)
        }
        .task { await model.refreshSocial() }
        .task { await refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, newPhase in
            // Back from Settings, where the switch may have changed.
            if newPhase == .active { Task { await refreshNotificationStatus() } }
        }
        .onChange(of: model.social) { reconcile() }
        .sheet(isPresented: $pickingBirthday) {
            BirthdayPicker()
        }
    }

    /// "3 друга", or the next step when there are none yet.
    private var finding: String {
        let count = model.social?.friends.count ?? model.friends.count
        guard count > 0 else { return "Найди друзей по юзернейму" }
        return "\(count)\(nbsp)\(Russian.plural(count, "друг", "друга", "друзей"))"
    }

    // MARK: - Your username

    private func usernameCard(_ username: String) -> some View {
        Card {
            HStack(spacing: 12) {
                Avatar(name: username, size: AvatarSize.regular)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Твой юзернейм")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                    Text(username)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.text)
                        .textSelection(.enabled)
                }
            }
            .accessibilityElement(children: .combine)

            ShareLink(item: "Найди меня в Locket: \(username)") {
                Text("Поделиться юзернеймом…")
            }
            .buttonStyle(LocketButtonStyle(.secondary))

            Button {
                if let id = model.myId { model.presentedWishlist = WishlistOwner(id: id, username: username) }
            } label: {
                Label("Мой виш-лист", systemImage: "scroll")
            }
            .buttonStyle(LocketButtonStyle(.secondary))

            // Friends hear about it a month before, 5 days before and on the day.
            Button {
                pickingBirthday = true
            } label: {
                Label(model.birthday.map { "День рождения — \($0.title)" } ?? "Указать день рождения", systemImage: "birthday.cake")
            }
            .buttonStyle(LocketButtonStyle(.secondary))
        }
    }

    // MARK: - Search

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: Space.header) {
            FormField(label: "Найти по юзернейму") {
                TextField("Найти по юзернейму", text: $query, prompt: Text("Например, барсук").foregroundStyle(Palette.faint))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
            }
            searchResults
        }
        .task(id: searchKey) { await runSearch() }
    }

    /// The query as the server reads it: no surrounding spaces, no leading "@".
    private var searchTerm: String {
        var term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if term.hasPrefix("@") { term.removeFirst() }
        return term.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchKey: SearchKey {
        SearchKey(term: searchTerm, attempt: searchAttempt)
    }

    @ViewBuilder
    private var searchResults: some View {
        switch searchPhase {
        case .idle:
            EmptyView()
        case .failed(let message):
            InlineError(message: "Поиск не удался. \(message)") {
                searchAttempt += 1
            }
        case .searching, .done:
            if !results.isEmpty {
                // Earlier results stay while the next query runs.
                Card {
                    ForEach(results) { user in
                        searchRow(user)
                    }
                }
            } else if searchPhase == .searching {
                Card {
                    skeletonRow(nameWidth: 120)
                }
                .appearsAfter()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Ищу…")
            } else {
                Text("Никого с таким юзернеймом — проверь буквы")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func searchRow(_ user: UserSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            personRow(user.username, status: user.relation == .outgoing ? "Заявка отправлена" : nil) {
                searchAction(user)
            }
            rowError(user.id)
        }
    }

    /// One action per result, by how you two are related. The change shows at once (see `run`).
    @ViewBuilder
    private func searchAction(_ user: UserSearchResult) -> some View {
        switch user.relation {
        case .none:
            Button("Добавить") { run(.add, userId: user.id) }
                .buttonStyle(LocketButtonStyle(.secondary, fullWidth: false))
        case .outgoing:
            Button("Отменить") { run(.cancel, userId: user.id) }
                .buttonStyle(LocketButtonStyle(.secondary, fullWidth: false))
        case .incoming:
            Button("Принять") { run(.accept, userId: user.id) }
                .buttonStyle(LocketButtonStyle(.secondary, fullWidth: false))
        case .friend:
            statusText("В друзьях")
        case .me:
            statusText("Это ты")
        }
    }

    /// Waits for typing to pause, then asks the server. A newer key cancels this task.
    private func runSearch() async {
        let term = searchTerm
        guard term.count >= 2 else {
            results = []
            searchPhase = .idle
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }
        searchPhase = .searching
        do {
            let found = try await model.searchUsers(term)
            guard !Task.isCancelled else { return }
            results = found
            searchPhase = .done
        } catch is CancellationError {
            // A newer query took over, or the session ended.
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            searchPhase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Requests and friends

    @ViewBuilder
    private var socialSections: some View {
        if let social = model.social {
            if case .failed(let message) = model.socialState {
                // What was loaded before stays below the error.
                socialError(message)
            }
            if !social.incoming.isEmpty {
                incomingSection(social.incoming)
            }
            if !social.outgoing.isEmpty {
                outgoingSection(social.outgoing)
            }
            friendsSection(social.friends)
        } else {
            section("В друзьях") {
                if case .failed(let message) = model.socialState {
                    socialError(message)
                } else {
                    friendsSkeleton
                }
            }
        }
    }

    private func socialError(_ message: String) -> some View {
        InlineError(message: "Не удалось загрузить друзей. \(message)") {
            Task { await model.refreshSocial() }
        }
    }

    private var friendsSkeleton: some View {
        Card {
            skeletonRow(nameWidth: 120)
            skeletonRow(nameWidth: 90)
            skeletonRow(nameWidth: 140)
        }
        .appearsAfter()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Загружаю друзей…")
    }

    private func incomingSection(_ requests: [FriendRequest]) -> some View {
        section("Заявки") {
            Card {
                ForEach(requests) { request in
                    incomingRow(request)
                }
            }
        }
    }

    private func incomingRow(_ request: FriendRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            personRow(request.username) { EmptyView() }
            buttonsLayout {
                Button {
                    run(.accept, userId: request.id)
                } label: {
                    ButtonLabel(title: "Принять", isLoading: busy[request.id] == .accept)
                }
                // Outlined like «Отклонить»: a screen gets one white button at most, and there can be many requests.
                .buttonStyle(LocketButtonStyle(.secondary))
                Button {
                    run(.decline, userId: request.id)
                } label: {
                    ButtonLabel(title: "Отклонить", isLoading: busy[request.id] == .decline)
                }
                .buttonStyle(LocketButtonStyle(.secondary))
            }
            .disabled(busy[request.id] != nil)
            rowError(request.id)
        }
    }

    private func outgoingSection(_ requests: [FriendRequest]) -> some View {
        section("Отправленные") {
            Card {
                ForEach(requests) { request in
                    outgoingRow(request)
                }
            }
        }
    }

    private func outgoingRow(_ request: FriendRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            personRow(request.username) {
                Button {
                    run(.cancel, userId: request.id)
                } label: {
                    ButtonLabel(title: "Отменить", isLoading: busy[request.id] == .cancel)
                }
                .buttonStyle(LocketButtonStyle(.secondary, fullWidth: false))
                .disabled(busy[request.id] != nil)
            }
            rowError(request.id)
        }
    }

    private func friendsSection(_ friends: [FriendEntry]) -> some View {
        section("В друзьях") {
            if friends.isEmpty {
                EmptyState(text: "Пока никого — найди друзей по юзернейму выше.")
            } else {
                Card {
                    ForEach(friends) { friend in
                        friendRow(friend)
                    }
                }
            }
        }
        .confirmationDialog(
            removalTitle,
            isPresented: removalPresented,
            titleVisibility: .visible,
            presenting: friendToRemove
        ) { friend in
            Button("Удалить", role: .destructive) {
                run(.remove, userId: friend.id)
            }
        } message: { _ in
            Text("Вы перестанете видеть фото друг друга.")
        }
    }

    private func friendRow(_ friend: FriendEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            personRow(friend.username, status: busy[friend.id] == .remove ? "Удаляю…" : Birthday(friend.birthday)?.friendLine) {
                HStack(spacing: 0) {
                    wishlistButton(friend)
                    friendMenu(friend)
                }
            }
            rowError(friend.id)
        }
    }

    /// The scroll next to a friend: their wishlist, with how many wishes are in it.
    private func wishlistButton(_ friend: FriendEntry) -> some View {
        let count = friend.wishCount ?? 0
        return Button {
            model.presentedWishlist = WishlistOwner(id: friend.id, username: friend.username)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "scroll")
                    .font(.body.weight(.semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(count > 0 ? Palette.text : Palette.muted)
            .padding(.horizontal, 6)
            .frame(minWidth: Space.hitTarget, minHeight: Space.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Виш-лист: \(friend.username)")
        .accessibilityValue(count > 0 ? WishlistView.count(count) : "пусто")
    }

    private func friendMenu(_ friend: FriendEntry) -> some View {
        Menu {
            Button("Удалить из друзей…", systemImage: "person.badge.minus", role: .destructive) {
                friendToRemove = friend
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .frame(width: Space.hitTarget, height: Space.hitTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Ещё: \(friend.username)")
        .disabled(busy[friend.id] != nil)
    }

    private var removalTitle: String {
        guard let friend = friendToRemove else { return "Удалить из друзей?" }
        return "Удалить «\(friend.username)» из друзей?"
    }

    private var removalPresented: Binding<Bool> {
        Binding(
            get: { friendToRemove != nil },
            set: { isPresented in
                if !isPresented { friendToRemove = nil }
            }
        )
    }

    // MARK: - Friend actions

    /// Runs a friend action for one person. A search result shows its new relation at once
    /// and gets the old one back if the server says no; the error goes under the row.
    private func run(_ action: FriendAction, userId: String) {
        guard busy[userId] == nil else { return }
        busy[userId] = action
        rowErrors[userId] = nil
        let previous = results.first(where: { $0.id == userId })?.relation
        switch action {
        case .add: setRelation(.outgoing, for: userId)
        case .accept: setRelation(.friend, for: userId)
        case .decline, .cancel, .remove: setRelation(.none, for: userId)
        }
        Task { @MainActor in
            do {
                try await perform(action, userId: userId)
                busy[userId] = nil
                reconcile()
            } catch {
                busy[userId] = nil
                if let previous { setRelation(previous, for: userId) }
                // CancellationError: the session lapsed and the app has signed out.
                if error is CancellationError { return }
                let message = "\(action.failure) \(error.localizedDescription)"
                rowErrors[userId] = message
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    private func perform(_ action: FriendAction, userId: String) async throws {
        switch action {
        case .add: try await model.sendFriendRequest(to: userId)
        case .accept: try await model.acceptFriendRequest(from: userId)
        case .decline, .cancel: try await model.deleteFriendRequest(with: userId)
        case .remove: try await model.removeFriend(userId)
        }
    }

    private func setRelation(_ relation: UserSearchResult.Relation, for userId: String) {
        guard let index = results.firstIndex(where: { $0.id == userId }) else { return }
        results[index].relation = relation
    }

    /// Brings search results in line with the latest friends and requests,
    /// leaving rows with an action still running alone.
    private func reconcile() {
        guard let social = model.social else { return }
        for index in results.indices {
            let user = results[index]
            guard busy[user.id] == nil, user.relation != .me else { continue }
            let latest = relation(of: user.id, in: social)
            if latest != user.relation { results[index].relation = latest }
        }
    }

    private func relation(of userId: String, in social: FriendsResponse) -> UserSearchResult.Relation {
        if social.friends.contains(where: { $0.id == userId }) { return .friend }
        if social.incoming.contains(where: { $0.id == userId }) { return .incoming }
        if social.outgoing.contains(where: { $0.id == userId }) { return .outgoing }
        return .none
    }

    // MARK: - Rows

    /// Side by side; stacked at the accessibility text sizes so nothing gets cut.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    private var buttonsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    /// A person: avatar, username, an optional status line, and the row's control on the right.
    private func personRow<Trailing: View>(
        _ username: String,
        status: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let trailingView = trailing()
        return rowLayout {
            HStack(spacing: 12) {
                Avatar(name: username, size: AvatarSize.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(username)
                        .font(.body)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    if let status {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            trailingView
                .layoutPriority(1)
        }
        .frame(minHeight: Space.hitTarget)
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Palette.muted)
            .frame(minHeight: Space.hitTarget)
    }

    @ViewBuilder
    private func rowError(_ userId: String) -> some View {
        if let message = rowErrors[userId] {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(Palette.negative)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func skeletonRow(nameWidth: CGFloat) -> some View {
        HStack(spacing: 12) {
            SkeletonBlock(width: AvatarSize.small, height: AvatarSize.small, cornerRadius: AvatarSize.small / 2)
            SkeletonBlock(width: nameWidth, height: 17)
        }
        .frame(minHeight: Space.hitTarget)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let contentView = content()
        return VStack(alignment: .leading, spacing: Space.header) {
            SectionHeader(title)
            contentView
        }
    }

    // MARK: - Notifications

    private var notifications: some View {
        section("Уведомления") {
            Card {
                if let notificationStatus {
                    notificationState(notificationStatus)
                } else {
                    SkeletonBlock(width: 220, height: 22)
                        .appearsAfter()
                }
                Text(lockScreenHint(reactions: ReactionKind.allCases.map(\.emoji).joined(separator: " ")))
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(lockScreenHint(reactions: ReactionKind.allCases.map(\.title).joined(separator: ", ")))
                Text("Добавь виджет Locket на экран «Домой»: там всегда последнее фото друзей и те же звёзды и реакции.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func notificationState(_ status: UNAuthorizationStatus) -> some View {
        switch status {
        case .denied:
            statusLabel("Уведомления выключены", systemImage: "bell.slash")
            Button("Открыть настройки уведомлений") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(LocketButtonStyle(.secondary))
        case .notDetermined:
            statusLabel("Уведомления ещё не включены", systemImage: "bell.slash")
            Button("Включить уведомления") {
                Task {
                    await PushRegistrar.requestPermissionAndRegister()
                    await refreshNotificationStatus()
                }
            }
            .buttonStyle(LocketButtonStyle(.secondary))
        default:
            statusLabel("Уведомления включены", systemImage: "bell")
        }
    }

    private func statusLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .foregroundStyle(Palette.text)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Palette.faint)
        }
        .font(.body)
    }

    /// How to rate from the lock screen; `reactions` are the marks on screen or their names for VoiceOver.
    private func lockScreenHint(reactions: String) -> String {
        "Когда друг выложит фото, удерживай уведомление на экране блокировки — появятся звёзды и реакции \(reactions). Оценка уходит сразу, приложение открывать не нужно."
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await PushRegistrar.authorizationStatus()
    }

    // MARK: - Exit

    private var exitButton: some View {
        Button {
            confirmSignOut = true
        } label: {
            ButtonLabel(title: "Выйти…", isLoading: signingOut)
        }
        .buttonStyle(LocketButtonStyle(.destructive))
        .disabled(signingOut)
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) {
                Task { @MainActor in
                    signingOut = true
                    await model.signOut()
                    signingOut = false
                }
            }
        } message: {
            Text("Чтобы вернуться, понадобится твой пароль. Восстановить его нельзя.")
        }
    }
}
