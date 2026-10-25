import SwiftUI
import UserNotifications

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    enum Phase: Equatable {
        case launching
        case offline(String)
        case signedOut
        /// The password is new: the account appears together with its first photo.
        case newAccount(password: String)
        case needsUsername
        case ready
    }

    enum Tab: Hashable {
        case camera, feed, week, day, friends
    }

    /// Where a block's data stands. Each block shows its own loading and error state.
    enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    /// A short non-blocking message at the top of the screen, also read out by VoiceOver.
    struct Toast: Equatable, Identifiable {
        let id = UUID()
        let text: String
        var isError = false
    }

    var phase: Phase = .launching
    private(set) var me: MeResponse?
    private(set) var feed: [Photo] = []
    private(set) var feedHasMore = true
    private(set) var isLoadingMore = false
    /// Older photos failed to load: the end of the feed shows it with a Retry.
    private(set) var loadMoreError: String?
    private(set) var feedState: LoadState = .idle
    private(set) var currentWeek: WeekResults?
    private(set) var history: [WeekResults] = []
    private(set) var weekState: LoadState = .idle
    /// Friends and requests, for the Friends tab.
    private(set) var social: FriendsResponse?
    private(set) var socialState: LoadState = .idle
    /// Today's «Кто лучше?» once it has arrived: shown at the top of the feed until you pick.
    private(set) var todayDuel: Duel?
    /// Your rated days, newest first: private, only you see them.
    private(set) var days: [DayRating] = []
    private(set) var daysState: LoadState = .idle

    var selectedTab: Tab = .camera
    var focusPhotoId: String?
    var presentedWeek: WeekResults?
    private(set) var toast: Toast?

    @ObservationIgnored private var deviceToken: String?
    @ObservationIgnored private var pendingWeekId: String?
    private let api = APIClient.shared
    private let pageSize = 30

    var myId: String? { me?.user.id }
    var username: String? { me?.user.username }
    var friends: [Friend] { me?.friends ?? [] }

    /// Requests waiting for you: the Friends tab badge.
    var incomingRequestCount: Int {
        if let social { return social.incoming.count }
        return me?.incomingRequests ?? 0
    }

    /// Friends' photos of this week you haven't rated yet: the feed's finding.
    var unratedCount: Int {
        feed.filter { $0.canReact && $0.myStars == 0 && $0.mine.isEmpty }.count
    }

    /// Friends' photos of this week still locked for you.
    var lockedCount: Int {
        guard let weekId = me?.week.id else { return 0 }
        return feed.filter { $0.locked && $0.weekId == weekId }.count
    }

    // MARK: - Session

    func start() async {
        guard TokenStore.token != nil else {
            phase = .signedOut
            return
        }
        do {
            apply(try await api.me())
        } catch APIError.unauthorized {
            signOutLocally()
        } catch {
            phase = .offline(error.localizedDescription)
        }
    }

    /// Keeps the offline screen up, with its button's own loading state, until start() decides.
    func retry() async {
        await start()
    }

    /// A known password signs in; an unknown one moves on to the first photo.
    func submitPassword(_ password: String) async throws {
        let auth = try await api.passwordAuth(password)
        if auth.status == .new {
            phase = .newAccount(password: password)
        } else {
            try await finishSignIn(auth)
        }
    }

    /// Back from the first photo to the password screen.
    func cancelNewAccount() {
        phase = .signedOut
    }

    /// Creates the account together with its first photo, which is published at once.
    func register(password: String, image: UIImage, caption: String) async throws {
        guard let jpeg = image.jpegData(compressionQuality: 0.82) else {
            throw APIError.server("Не получилось подготовить фото.")
        }
        let auth = try await api.register(password: password, jpeg: jpeg, caption: caption)
        try await finishSignIn(auth)
        // Someone signed up with this password a moment earlier: that account is theirs, the photo went there.
        if auth.status == .signedIn {
            show(toast: "Такой пароль уже есть — ты вошёл, фото отправлено друзьям")
        }
    }

    private func finishSignIn(_ auth: PasswordAuthResponse) async throws {
        guard let token = auth.token, let newMe = auth.me else {
            throw APIError.server("Сервер ответил непонятно. Попробуй ещё раз.")
        }
        TokenStore.token = token
        apply(newMe)
        await uploadDeviceToken()
    }

    /// Three free usernames: an animal, a swear word, a name.
    func usernameSuggestions() async throws -> [UsernameSuggestion] {
        try await signedIn { try await self.api.usernameSuggestions() }
    }

    func chooseUsername(_ username: String) async throws {
        let newMe = try await signedIn { try await self.api.chooseUsername(username) }
        apply(newMe)
    }

    func signOut() async {
        try? await api.logout(deviceToken: deviceToken)
        signOutLocally()
    }

    private func signOutLocally() {
        TokenStore.token = nil
        me = nil
        resetUserData()
        selectedTab = .camera
        phase = .signedOut
    }

    private func resetUserData() {
        feed = []
        feedHasMore = true
        loadMoreError = nil
        feedState = .idle
        currentWeek = nil
        history = []
        weekState = .idle
        social = nil
        socialState = .idle
        days = []
        daysState = .idle
        todayDuel = nil
        WidgetRefresh.now()
    }

    private func apply(_ newMe: MeResponse) {
        if let old = me, old.user.id != newMe.user.id { resetUserData() }
        me = newMe
        phase = newMe.user.username == nil ? .needsUsername : .ready
        // The browser demo has no pushes: skip the permission prompt there.
        if phase == .ready && !AppConfig.isDemo {
            Task {
                await PushRegistrar.requestPermissionAndRegister()
                // The evening «Оцени свой день» lives on the phone.
                await DayReminder.schedule()
            }
        }
    }

    /// A background load: a failure is not a toast. The friends list keeps what it had.
    func refreshMe() async {
        do {
            apply(try await api.me())
        } catch {
            _ = loadFailure(error)
        }
    }

    func refreshAll() async {
        await refreshMe()
        await refreshFeed()
        await refreshWeek()
        await refreshSocial()
        await refreshDays()
        await refreshDuel()
    }

    // MARK: - «Кто лучше?»

    /// A background load: nothing to show on failure, the card simply doesn't appear.
    func refreshDuel() async {
        guard phase == .ready else { return }
        do {
            todayDuel = try await api.todayDuel()
        } catch {
            _ = loadFailure(error)
        }
    }

    /// Throws so the card can say what went wrong.
    func chooseDuel(_ pick: DuelPick) async throws {
        guard let duel = todayDuel, duel.choice == nil else { return }
        let saved = try await signedIn { try await self.api.chooseDuel(id: duel.id, pick: pick) }
        todayDuel = saved
        if let name = saved?.chosen?.username {
            show(toast: "Выбор сохранён: \(name)")
        }
    }

    // MARK: - Day rating

    /// A rated day by its "yyyy-MM-dd" key.
    func day(_ key: String) -> DayRating? {
        days.first { $0.date == key }
    }

    /// A background load: the «День» tab shows the error inline with a Retry.
    func refreshDays() async {
        guard phase == .ready else { return }
        if daysState != .loaded { daysState = .loading }
        do {
            days = try await api.days()
            daysState = .loaded
        } catch {
            if let message = loadFailure(error) { daysState = .failed(message) }
        }
    }

    /// Throws so the «День» tab can show the error under the form.
    func saveDay(_ rating: DayRating) async throws {
        let saved = try await signedIn { try await self.api.saveDay(rating) }
        days.removeAll { $0.date == saved.date }
        days.append(saved)
        days.sort { $0.date > $1.date }
    }

    /// For calls that throw so the screen can show the error next to what failed.
    /// A lapsed session signs out and throws CancellationError (nothing to show).
    private func signedIn<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            if (error as? APIError) == .unauthorized {
                signOutLocally()
                throw CancellationError()
            }
            throw error
        }
    }

    // MARK: - Friends

    /// A background load: the Friends tab shows the error inline with a Retry.
    func refreshSocial() async {
        guard phase == .ready else { return }
        if socialState != .loaded { socialState = .loading }
        do {
            social = try await api.friends()
            socialState = .loaded
        } catch {
            if let message = loadFailure(error) { socialState = .failed(message) }
        }
    }

    func searchUsers(_ query: String) async throws -> [UserSearchResult] {
        try await signedIn { try await self.api.searchUsers(query) }
    }

    /// If they had already asked you, this makes you friends at once.
    func sendFriendRequest(to userId: String) async throws {
        let response = try await signedIn { try await self.api.sendFriendRequest(userId: userId) }
        let becameFriends = response.friends.contains { $0.id == userId }
        friendsChanged(response, refreshPhotos: becameFriends)
    }

    func acceptFriendRequest(from userId: String) async throws {
        let response = try await signedIn { try await self.api.acceptFriendRequest(userId: userId) }
        friendsChanged(response, refreshPhotos: true)
    }

    /// Declines an incoming request or cancels an outgoing one.
    func deleteFriendRequest(with userId: String) async throws {
        let response = try await signedIn { try await self.api.deleteFriendRequest(userId: userId) }
        friendsChanged(response, refreshPhotos: false)
    }

    func removeFriend(_ userId: String) async throws {
        let response = try await signedIn { try await self.api.removeFriend(userId: userId) }
        friendsChanged(response, refreshPhotos: true)
    }

    // MARK: - Wishlists

    func wishlist(of userId: String) async throws -> [Wish] {
        try await signedIn { try await self.api.wishlist(of: userId) }
    }

    /// `jpeg` is the optional picture.
    func addWish(title: String, url: String, jpeg: Data?) async throws -> Wish {
        try await signedIn { try await self.api.addWish(title: title, url: url, jpeg: jpeg) }
    }

    func deleteWish(id: String) async throws {
        try await signedIn { try await self.api.deleteWish(id: id) }
    }

    /// Shows the server's answer at once; the rest catches up in the background.
    private func friendsChanged(_ response: FriendsResponse, refreshPhotos: Bool) {
        social = response
        socialState = .loaded
        Task {
            await refreshMe()
            if refreshPhotos {
                await refreshFeed()
                await refreshWeek()
            }
        }
    }

    // MARK: - Feed

    func refreshFeed() async {
        guard phase == .ready else { return }
        if feedState != .loaded { feedState = .loading }
        do {
            let photos = try await api.photos()
            feed = photos
            feedHasMore = photos.count >= pageSize
            feedState = .loaded
            WidgetRefresh.now()
        } catch {
            // Photos already on screen stay; the block shows the error with a Retry.
            if let message = loadFailure(error) { feedState = .failed(message) }
        }
    }

    func loadMoreIfNeeded(after photo: Photo) async {
        guard feedHasMore, !isLoadingMore, photo.id == feed.last?.id else { return }
        isLoadingMore = true
        loadMoreError = nil
        defer { isLoadingMore = false }
        do {
            let more = try await api.photos(before: photo.createdAt)
            let known = Set(feed.map(\.id))
            feed += more.filter { !known.contains($0.id) }
            feedHasMore = more.count >= pageSize
        } catch {
            loadMoreError = loadFailure(error)
        }
    }

    /// Retry for the end of the feed.
    func retryLoadMore() async {
        guard let last = feed.last else { return }
        await loadMoreIfNeeded(after: last)
    }

    func upload(_ image: UIImage, caption: String) async throws {
        guard let jpeg = image.jpegData(compressionQuality: 0.82) else {
            throw APIError.server("Не получилось подготовить фото.")
        }
        let response = try await api.upload(jpeg: jpeg, caption: caption)
        feed.removeAll { $0.id == response.photo.id }
        feed.insert(response.photo, at: 0)
        let unlocked = response.unlocked
        if unlocked > 0 {
            // "фото" doesn't decline, so no plural forms are needed.
            show(toast: "Фото отправлено — открылось \(unlocked)\(nbsp)фото друзей")
        } else {
            show(toast: "Фото отправлено друзьям")
        }
        // Posting opens friends' locked photos, so the whole feed changes.
        Task {
            await refreshFeed()
            await refreshWeek()
        }
    }

    func toggle(_ kind: ReactionKind, on photo: Photo) async {
        let turnOn = !photo.mine.contains(kind)
        let mine = turnOn ? photo.mine + [kind] : photo.mine.filter { $0 != kind }
        await rate(photo, MyRating(myStars: photo.myStars, mine: mine)) {
            try await self.api.react(kind, on: turnOn, photoId: photo.id)
        }
    }

    /// Tapping the star you already gave clears the rating.
    func setStars(_ stars: Int, on photo: Photo) async {
        let value = stars == photo.myStars ? 0 : stars
        await rate(photo, MyRating(myStars: value, mine: photo.mine)) {
            try await self.api.setStars(value, photoId: photo.id)
        }
    }

    /// Shows the new rating at once, then replaces it with what the server says.
    private func rate(_ photo: Photo, _ optimistic: MyRating, request: () async throws -> Photo) async {
        guard let index = feed.firstIndex(where: { $0.id == photo.id }) else { return }
        let original = feed[index]
        feed[index].apply(optimistic)
        do {
            let updated = try await request()
            replace(updated)
            WidgetRefresh.now()
        } catch {
            replace(original)
            if !(error is CancellationError) {
                show(error: "Оценка не сохранилась: \(error.localizedDescription)")
            }
        }
    }

    func delete(_ photo: Photo) async {
        await perform {
            try await self.api.deletePhoto(id: photo.id)
            self.feed.removeAll { $0.id == photo.id }
        }
    }

    private func replace(_ photo: Photo) {
        if let index = feed.firstIndex(where: { $0.id == photo.id }) { feed[index] = photo }
    }

    // MARK: - Week

    func refreshWeek() async {
        guard phase == .ready else { return }
        if weekState != .loaded { weekState = .loading }
        let api = self.api
        do {
            async let current = api.currentWeek()
            async let past = api.weeks()
            let (week, weeks) = try await (current, past)
            currentWeek = week
            history = weeks
            weekState = .loaded
        } catch {
            if let message = loadFailure(error) { weekState = .failed(message) }
        }
        if let id = pendingWeekId, let week = history.first(where: { $0.weekId == id }) {
            pendingWeekId = nil
            presentedWeek = week
        }
    }

    // MARK: - Push notifications

    func registerDevice(token: String) async {
        deviceToken = token
        await uploadDeviceToken()
    }

    private func uploadDeviceToken() async {
        guard let deviceToken, TokenStore.token != nil else { return }
        try? await api.registerDevice(token: deviceToken, environment: PushRegistrar.environment)
    }

    /// A push arrived while the app is on screen.
    func pushArrived(_ push: PushInfo) {
        switch push.type {
        case "photo", "reaction", "locked":
            Task { await refreshFeed() }
        case "friend_request":
            Task {
                await refreshMe()
                await refreshSocial()
            }
        case "friend_accepted":
            Task {
                await refreshMe()
                await refreshSocial()
                await refreshFeed()
                await refreshWeek()
            }
        case "weekly":
            Task { await refreshWeek() }
        case "duel":
            Task { await refreshDuel() }
        default:
            break
        }
    }

    /// A tap on the notification, or "Принять" on a friend request — which may run
    /// with the app launched in the background: the request only needs the stored token.
    func handleNotificationResponse(action: String, push: PushInfo) async {
        if action == PushCategories.acceptFriendAction {
            if let userId = push.userId {
                try? await acceptFriendRequest(from: userId)
            }
        } else if action == UNNotificationDefaultActionIdentifier {
            open(push)
        }
    }

    func open(_ push: PushInfo) {
        switch push.type {
        case "photo", "reaction":
            selectedTab = .feed
            focusPhotoId = push.photoId
            Task { await refreshFeed() }
        case "weekly":
            selectedTab = .week
            pendingWeekId = push.weekId
            Task { await refreshWeek() }
        case "locked":
            // Posting is what opens it.
            selectedTab = .camera
            Task { await refreshFeed() }
        case "reminder":
            selectedTab = .feed
        case "friend_request", "friend_accepted":
            selectedTab = .friends
            Task { await refreshSocial() }
        case "day":
            selectedTab = .day
            Task { await refreshDays() }
        case "duel":
            // The pick waits at the top of the feed.
            selectedTab = .feed
            Task { await refreshDuel() }
        default:
            break
        }
    }

    /// locket://photo/<id> (from the widget) and locket://week
    func open(url: URL) {
        guard url.scheme == "locket" else { return }
        switch url.host() {
        case "photo": open(PushInfo(type: "photo", photoId: url.lastPathComponent))
        case "week": selectedTab = .week
        default: break
        }
    }

    // MARK: - UI helpers

    func show(toast text: String) {
        present(Toast(text: text))
    }

    func show(error text: String) {
        present(Toast(text: text, isError: true))
    }

    func dismissToast() {
        toast = nil
    }

    private func present(_ newToast: Toast) {
        toast = newToast
        AccessibilityNotification.Announcement(newToast.text).post()
        Task {
            try? await Task.sleep(for: .seconds(newToast.isError ? 5 : 2.5))
            if toast?.id == newToast.id { toast = nil }
        }
    }

    /// The message for a block that failed to load, or nil when there is nothing to show.
    private func loadFailure(_ error: Error) -> String? {
        if error is CancellationError { return nil }
        if (error as? APIError) == .unauthorized {
            signOutLocally()
            return nil
        }
        return error.localizedDescription
    }

    /// Runs an action the person started; a failure becomes an error toast.
    private func perform(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            if let message = loadFailure(error) { show(error: message) }
        }
    }
}
