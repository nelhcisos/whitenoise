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

    var phase: Phase = .launching
    private(set) var me: MeResponse?
    private(set) var feed: [Photo] = []
    private(set) var feedHasMore = true
    private(set) var isLoadingMore = false
    private(set) var currentWeek: WeekResults?
    private(set) var history: [WeekResults] = []

    var selectedTab: Tab = .camera
    var focusPhotoId: String?
    var presentedWeek: WeekResults?
    var toast: String?
    var alert: String?

    @ObservationIgnored private var deviceToken: String?
    @ObservationIgnored private var pendingWeekId: String?
    private let api = APIClient.shared
    private let pageSize = 30

    var myId: String? { me?.user.id }
    var circle: FriendCircle? { me?.circle }
    var members: [Member] { me?.members ?? [] }

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
        currentWeek = nil
        history = []
        SharedPhotoStore.clear()
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
        await perform {
            let photos = try await self.api.photos()
            self.feed = photos
            self.feedHasMore = photos.count >= self.pageSize
            self.updateWidget()
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
        show(toast: "Отправлено друзьям 💛")
        Task { await refreshWeek() }
    }

    func toggle(_ kind: ReactionKind, on photo: Photo) async {
        guard let index = feed.firstIndex(where: { $0.id == photo.id }) else { return }
        let original = feed[index]
        let turnOn = !original.mine.contains(kind)

        // Optimistic update so the button reacts instantly.
        if turnOn {
            feed[index].mine.append(kind)
            feed[index].counts[kind] += 1
        } else {
            feed[index].mine.removeAll { $0 == kind }
            feed[index].counts[kind] = max(0, feed[index].counts[kind] - 1)
        }

        do {
            let updated = try await api.react(kind, on: turnOn, photoId: photo.id)
            replace(updated)
            SharedPhotoStore.updateReactions(photoId: updated.id, mine: updated.mine)
            Task { await refreshWeek() }
        } catch {
            replace(original)
            if !(error is CancellationError) { alert = error.localizedDescription }
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

    /// Keeps the home-screen widget on the newest photo from a friend.
    private func updateWidget() {
        guard let myId, let latest = feed.first(where: { $0.authorId != myId }) else { return }
        let snapshot = WidgetPhoto(
            photoId: latest.id,
            authorName: latest.authorName,
            caption: latest.caption,
            createdAt: latest.date,
            mine: latest.mine,
            canReact: latest.canReact
        )
        let stored = SharedPhotoStore.load()
        if let stored, stored.photoId == latest.id {
            if stored != snapshot { SharedPhotoStore.saveMeta(snapshot) }
            return
        }
        if let stored, stored.createdAt > latest.date { return }
        let url = latest.imageUrl
        Task.detached(priority: .utility) {
            guard let result = try? await URLSession.shared.data(from: url) else { return }
            SharedPhotoStore.save(snapshot, imageData: result.0)
        }
    }

    // MARK: - Week

    func refreshWeek() async {
        guard phase == .ready else { return }
        let api = self.api
        await perform {
            async let current = api.currentWeek()
            async let past = api.weeks()
            let (week, weeks) = try await (current, past)
            self.currentWeek = week
            self.history = weeks
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
        if let kind = ReactionKind(notificationActionID: action), let photoId = push.photoId {
            await rateFromNotification(kind, photoId: photoId)
        } else if action == UNNotificationDefaultActionIdentifier {
            open(push)
        }
    }

    /// 🔥 / 🎨 / 😂 tapped on a notification. The app may have been launched in
    /// the background just for this, so it only touches the network and the widget.
    private func rateFromNotification(_ kind: ReactionKind, photoId: String) async {
        let app = UIApplication.shared
        let task = app.beginBackgroundTask(withName: "rate-photo", expirationHandler: nil)
        defer { app.endBackgroundTask(task) }
        do {
            let mine = try await ReactionAPI.set(kind, on: true, photoId: photoId)
            SharedPhotoStore.updateReactions(photoId: photoId, mine: mine)
            if let index = feed.firstIndex(where: { $0.id == photoId }), !feed[index].mine.contains(kind) {
                feed[index].mine = mine
                feed[index].counts[kind] += 1
            }
        } catch {
            let content = UNMutableNotificationContent()
            content.title = "Оценка не отправилась"
            content.body = "\(error.localizedDescription) Открой Locket и оцени ещё раз."
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
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
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast == text { toast = nil }
        }
    }

    private func perform(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch is CancellationError {
        } catch APIError.unauthorized {
            signOutLocally()
        } catch {
            alert = error.localizedDescription
        }
    }
}
