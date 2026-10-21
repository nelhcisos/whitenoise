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
        case needsCircle
        case ready
    }

    enum Tab: Hashable {
        case camera, feed, week, friends
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
    private(set) var feedState: LoadState = .idle
    private(set) var currentWeek: WeekResults?
    private(set) var history: [WeekResults] = []
    private(set) var weekState: LoadState = .idle

    var selectedTab: Tab = .camera
    var focusPhotoId: String?
    var presentedWeek: WeekResults?
    private(set) var toast: Toast?

    @ObservationIgnored private var deviceToken: String?
    @ObservationIgnored private var pendingWeekId: String?
    private let api = APIClient.shared
    private let pageSize = 30

    var myId: String? { me?.user.id }
    var circle: FriendCircle? { me?.circle }
    var members: [Member] { me?.members ?? [] }

    /// Friends' photos of this week you haven't rated yet: the feed's finding.
    var unratedCount: Int {
        feed.filter { $0.canReact && $0.myStars == 0 && $0.mine.isEmpty }.count
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

    func retry() async {
        phase = .launching
        await start()
    }

    func signIn(email: String, password: String) async throws {
        let auth = try await api.login(email: email.trimmingCharacters(in: .whitespaces), password: password)
        TokenStore.token = auth.token
        apply(auth.me)
        await uploadDeviceToken()
    }

    func signUp(name: String, email: String, password: String) async throws {
        let auth = try await api.register(
            name: name.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces),
            password: password
        )
        TokenStore.token = auth.token
        apply(auth.me)
        await uploadDeviceToken()
    }

    func signOut() async {
        try? await api.logout(deviceToken: deviceToken)
        signOutLocally()
    }

    private func signOutLocally() {
        TokenStore.token = nil
        me = nil
        resetCircleData()
        selectedTab = .camera
        phase = .signedOut
    }

    private func resetCircleData() {
        feed = []
        feedHasMore = true
        feedState = .idle
        currentWeek = nil
        history = []
        weekState = .idle
        WidgetRefresh.now()
    }

    private func apply(_ newMe: MeResponse) {
        if let old = me, old.circle?.id != newMe.circle?.id { resetCircleData() }
        me = newMe
        phase = newMe.circle == nil ? .needsCircle : .ready
        if phase == .ready {
            Task { await PushRegistrar.requestPermissionAndRegister() }
        }
    }

    func refreshMe() async {
        await perform { self.apply(try await self.api.me()) }
    }

    func refreshAll() async {
        await refreshMe()
        await refreshFeed()
        await refreshWeek()
    }

    // MARK: - Circle & profile

    func createCircle(name: String) async throws {
        apply(try await api.createCircle(name: name))
    }

    func joinCircle(code: String) async throws {
        apply(try await api.joinCircle(code: code))
    }

    func leaveCircle() async {
        await perform { self.apply(try await self.api.leaveCircle()) }
    }

    func renameMe(_ name: String) async {
        await perform { self.apply(try await self.api.rename(name)) }
    }

    func renameCircle(_ name: String) async {
        await perform { self.apply(try await self.api.renameCircle(name)) }
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
        defer { isLoadingMore = false }
        await perform {
            let more = try await self.api.photos(before: photo.createdAt)
            let known = Set(self.feed.map(\.id))
            self.feed += more.filter { !known.contains($0.id) }
            self.feedHasMore = more.count >= self.pageSize
        }
    }

    func upload(_ image: UIImage, caption: String) async throws {
        guard let jpeg = image.jpegData(compressionQuality: 0.82) else {
            throw APIError.server("Не получилось подготовить фото.")
        }
        let photo = try await api.upload(jpeg: jpeg, caption: caption)
        feed.insert(photo, at: 0)
        show(toast: "Фото отправлено друзьям")
        Task { await refreshWeek() }
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
            Task { await refreshWeek() }
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
        case "photo", "reaction": Task { await refreshFeed() }
        case "weekly": Task { await refreshWeek() }
        case "join": Task { await refreshMe() }
        default: break
        }
    }

    func handleNotificationResponse(action: String, push: PushInfo) async {
        if action == UNNotificationDefaultActionIdentifier { open(push) }
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
        case "reminder":
            selectedTab = .feed
        case "join":
            selectedTab = .friends
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
