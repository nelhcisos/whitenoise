import Foundation

/// In-memory stand-in for the server, for the browser demo (AppConfig.isDemo).
/// Answers the same paths with the same JSON and rules as server/src/app.js
/// (see locket/API.md), so the rest of the app can't tell the difference.
///
/// Seed: password «1234» is the ready-made account «барсук». Any other password
/// makes a new account, which gets ярослава and ёжик as friends and a request
/// from добрыня once it picks a username. Strangers accept requests after a
/// few seconds; ярослава rates your new photos shortly after you post.
actor DemoBackend {
    static let shared = DemoBackend()

    typealias Reply = (status: Int, data: Data)

    // MARK: - State

    private struct User {
        let id: String
        var username: String?
        let password: String?
    }

    private struct Photo {
        let id: String
        let authorId: String
        let weekId: String
        let caption: String?
        let url: URL
        let createdAt: Double
        let seq: Int
    }

    private struct Star {
        let photoId: String
        let userId: String
        var value: Int
        let at: Double
    }

    private struct Reaction {
        let photoId: String
        let userId: String
        let kind: String
        let at: Double
    }

    private struct Request {
        let from: String
        let to: String
        let at: Double
    }

    private enum Event {
        case accept(stranger: String, user: String)
        case rate(photoId: String, by: String)
    }

    private var users: [String: User] = [:]
    private var friendships: [String: Double] = [:] // "a|b" (sorted) → since
    private var requests: [Request] = []
    private var photos: [Photo] = []
    private var stars: [Star] = []
    private var reactions: [Reaction] = []
    private var events: [(due: Date, event: Event)] = []
    /// «Кто лучше?»: every pick made, and today's pair per person.
    private struct DuelRecord {
        let id: String
        let userId: String
        let date: String
        let left: String
        let right: String
        var choice: String?
        var chosenId: String?
        var weekId: String?
    }
    private var duels: [DuelRecord] = []

    /// userId → date → the day's rating JSON, as the server would return it.
    private var days: [String: [String: [String: Any]]] = [:]
    private var currentUserId: String?
    private var seeded = false
    private var seq = 0

    private let currentWeek = "demo-current"
    private let previousWeek = "demo-previous"
    private var weekStart: Double = 0
    private var weekEnd: Double = 0

    private static let kinds = ["creative", "funny", "wild"]

    // MARK: - Entry point

    /// `path` as APIClient passes it, e.g. "api/friends/requests/<id>/accept".
    func respond(method: String, path: String, query: [URLQueryItem], body: Data?) -> Reply {
        seedIfNeeded()
        runDueEvents()
        let parts = path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        let input = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        let q = Dictionary(query.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
        // The "*" segments of a matching route, or nil.
        func route(_ verb: String, _ pattern: String) -> [String]? {
            verb == method ? Self.match(parts, pattern) : nil
        }

        if route("POST", "api/auth/password") != nil { return signIn(password: input["password"]) }
        if route("POST", "api/auth/register") != nil { return register(input) }
        if route("POST", "api/auth/logout") != nil {
            currentUserId = nil
            return reply(["ok": true])
        }

        guard let me = currentUserId.flatMap({ users[$0] }) else {
            return failure(401, "Нужно войти заново")
        }

        // Allowed before a username is chosen.
        if route("GET", "api/me") != nil { return reply(meJSON(me)) }
        if route("GET", "api/usernames/suggestions") != nil {
            if me.username != nil { return failure(409, "Юзернейм уже выбран") }
            return reply(["suggestions": suggestions()])
        }
        if route("POST", "api/me/username") != nil { return chooseUsername(me, input["username"]) }
        if route("POST", "api/devices") != nil || route("DELETE", "api/devices/*") != nil { return reply(["ok": true]) }
        if route("GET", "api/widget") != nil {
            guard me.username != nil else { return reply(["photo": NSNull()]) }
            let newest = feedPhotos(authors: friendIds(me.id), before: .greatestFiniteMagnitude, limit: 100)
                .first { isOpen($0, for: me.id) }
            return reply(["photo": newest.map { photoJSON($0, viewer: me.id) as Any } ?? NSNull()])
        }

        guard me.username != nil else { return failure(409, "Сначала выбери юзернейм") }

        // Friends
        if route("GET", "api/users/search") != nil { return reply(["users": search(q["q"] ?? "", viewer: me.id)]) }
        if route("GET", "api/friends") != nil { return reply(friendsJSON(me.id)) }
        if route("POST", "api/friends/requests") != nil { return sendRequest(from: me, to: string(input["userId"])) }
        if let ids = route("POST", "api/friends/requests/*/accept") {
            let other = ids[0]
            guard requests.contains(where: { $0.from == other && $0.to == me.id }) else {
                return failure(404, "Заявка не найдена")
            }
            befriend(me.id, other)
            return reply(friendsJSON(me.id))
        }
        if let ids = route("DELETE", "api/friends/requests/*") {
            let other = ids[0]
            requests.removeAll { ($0.from == me.id && $0.to == other) || ($0.from == other && $0.to == me.id) }
            return reply(friendsJSON(me.id))
        }
        if let ids = route("DELETE", "api/friends/*") {
            friendships[pairKey(me.id, ids[0])] = nil
            return reply(friendsJSON(me.id))
        }

        // Photos
        if route("GET", "api/photos") != nil {
            let before = Double(q["before"] ?? "") ?? .greatestFiniteMagnitude
            let limit = min(max(Int(q["limit"] ?? "") ?? 30, 1), 100)
            let list = feedPhotos(authors: [me.id] + friendIds(me.id), before: before, limit: limit)
            return reply(["photos": list.map { photoJSON($0, viewer: me.id) }])
        }
        if route("POST", "api/photos") != nil {
            guard let jpeg = body, isJPEG(jpeg) else { return failure(400, "Нужна картинка в формате JPEG") }
            let result = publish(author: me.id, jpeg: jpeg, caption: cleanCaption(q["caption"]))
            return reply(["photo": photoJSON(result.photo, viewer: me.id), "unlocked": result.unlocked])
        }
        if let ids = route("GET", "api/photos/*") {
            guard let photo = visiblePhoto(ids[0], viewer: me.id) else { return failure(404, "Фото не найдено") }
            return reply(["photo": photoJSON(photo, viewer: me.id)])
        }
        if let ids = route("DELETE", "api/photos/*") {
            let id = ids[0]
            guard let photo = visiblePhoto(id, viewer: me.id) else { return failure(404, "Фото не найдено") }
            guard photo.authorId == me.id else { return failure(403, "Удалять можно только свои фото") }
            photos.removeAll { $0.id == id }
            stars.removeAll { $0.photoId == id }
            reactions.removeAll { $0.photoId == id }
            return reply(["ok": true])
        }
        if let ids = route("PUT", "api/photos/*/stars") {
            return rateStars(ids[0], viewer: me.id, value: int(input["stars"]), clearing: false)
        }
        if let ids = route("DELETE", "api/photos/*/stars") {
            return rateStars(ids[0], viewer: me.id, value: 0, clearing: true)
        }
        if let ids = route("PUT", "api/photos/*/reactions/*") {
            return react(ids[0], viewer: me.id, kind: ids[1], on: true)
        }
        if let ids = route("DELETE", "api/photos/*/reactions/*") {
            return react(ids[0], viewer: me.id, kind: ids[1], on: false)
        }

        // «Кто лучше?»: in the demo today's pair is waiting at once (no push, no random moment).
        if route("GET", "api/duels/today") != nil {
            return reply(["duel": todayDuel(for: me.id).map { duelJSON($0) as Any } ?? NSNull()])
        }
        if let ids = route("POST", "api/duels/*/choice") {
            guard let index = duels.firstIndex(where: { $0.id == ids[0] && $0.userId == me.id }) else {
                return failure(404, "Выбор не найден")
            }
            let pick = string(input["pick"])
            guard pick == "left" || pick == "right" else { return failure(400, "Выбери левого или правого") }
            guard duels[index].choice == nil else { return failure(409, "Выбор уже сделан") }
            duels[index].choice = pick
            duels[index].chosenId = pick == "left" ? duels[index].left : duels[index].right
            duels[index].weekId = currentWeek
            return reply(["duel": duelJSON(duels[index])])
        }

        // The day rating: private, only its owner reads it.
        if let ids = route("PUT", "api/days/*") {
            return saveDay(user: me.id, date: ids[0], input: input)
        }
        if route("GET", "api/days") != nil {
            let limit = min(max(Int(q["limit"] ?? "") ?? 30, 1), 120)
            let list = (days[me.id] ?? [:]).values.sorted { ($0["date"] as? String ?? "") > ($1["date"] as? String ?? "") }
            return reply(["days": Array(list.prefix(limit))])
        }

        // Weeks
        if route("GET", "api/week/current") != nil {
            return reply(weekResults(viewer: me.id, weekId: currentWeek, closedAt: nil))
        }
        if route("GET", "api/weeks") != nil {
            let past = weekResults(viewer: me.id, weekId: previousWeek, closedAt: weekStart)
            let count = past["photoCount"] as? Int ?? 0
            let weeks: [[String: Any]] = count > 0 ? [past] : []
            return reply(["weeks": weeks])
        }
        if let ids = route("GET", "api/weeks/*") {
            if ids[0] == currentWeek { return reply(weekResults(viewer: me.id, weekId: currentWeek, closedAt: nil)) }
            if ids[0] == previousWeek { return reply(weekResults(viewer: me.id, weekId: previousWeek, closedAt: weekStart)) }
            return failure(404, "Неделя не найдена")
        }
        return failure(404, "Не найдено")
    }

    /// "api/photos/*/stars" against the path segments; returns what the "*" matched.
    private static func match(_ parts: [String], _ pattern: String) -> [String]? {
        let expected = pattern.split(separator: "/").map(String.init)
        guard expected.count == parts.count else { return nil }
        var captured: [String] = []
        for (want, got) in zip(expected, parts) {
            if want == "*" {
                captured.append(got)
            } else if want != got {
                return nil
            }
        }
        return captured
    }

    // MARK: - «Кто лучше?»

    private func todayDuel(for userId: String) -> DuelRecord? {
        let date = DayRating.key(for: Date())
        if let existing = duels.first(where: { $0.userId == userId && $0.date == date }) { return existing }
        let friends = friendIds(userId).shuffled()
        guard friends.count >= 2 else { return nil }
        let record = DuelRecord(id: UUID().uuidString.lowercased(), userId: userId, date: date, left: friends[0], right: friends[1])
        duels.append(record)
        return record
    }

    private func duelJSON(_ d: DuelRecord) -> [String: Any] {
        [
            "id": d.id,
            "date": d.date,
            "left": ["id": d.left, "username": users[d.left]?.username ?? ""],
            "right": ["id": d.right, "username": users[d.right]?.username ?? ""],
            "choice": d.choice.map { $0 as Any } ?? NSNull(),
        ]
    }

    /// Most picked in the week among these people; ties go by the leaderboard. Only the winner is told.
    private func favoriteFriend(weekId: String, circle: Set<String>, order: [Stat]) -> Any {
        var picks: [String: Int] = [:]
        for d in duels where d.weekId == weekId {
            if let chosen = d.chosenId, circle.contains(chosen) { picks[chosen, default: 0] += 1 }
        }
        var winner: (id: String, name: String, count: Int)?
        for s in order {
            let count = picks[s.userId] ?? 0
            if count > 0 && count > (winner?.count ?? 0) { winner = (s.userId, s.name, count) }
        }
        guard let winner else { return NSNull() }
        return ["userId": winner.id, "name": winner.name, "value": winner.count] as [String: Any]
    }

    // MARK: - Day rating

    private static let dayReasons = ["unchanged", "distracted", "awkward", "odor", "issues", "reckless", "noChance", "fatigued", "gps", "rude"]
    private static let dayHighlights = ["advice", "polite", "comfort", "clean", "conversation", "music"]

    private func saveDay(user: String, date: String, input: [String: Any]) -> Reply {
        guard date.count == 10, DayRating.date(of: date) != nil else { return failure(400, "Неверная дата") }
        let stars = int(input["stars"])
        guard (1...5).contains(stars) else { return failure(400, "Звёзд может быть от 1 до 5") }
        let reasons = (input["reasons"] as? [String]) ?? []
        let liked = (input["liked"] as? [String]) ?? []
        if reasons.contains(where: { !Self.dayReasons.contains($0) }) || liked.contains(where: { !Self.dayHighlights.contains($0) }) {
            return failure(400, "Неизвестный вариант оценки")
        }
        let day: [String: Any] = [
            "date": date,
            "stars": stars,
            "reasons": stars < 5 ? Self.dayReasons.filter { reasons.contains($0) } : [String](),
            "liked": stars == 5 ? Self.dayHighlights.filter { liked.contains($0) } : [String](),
            "condition": (input["condition"] as? Bool).map { $0 as Any } ?? NSNull(),
            "place": (input["place"] as? Bool).map { $0 as Any } ?? NSNull(),
            "updatedAt": nowMs(),
        ]
        days[user, default: [:]][date] = day
        return reply(["day": day])
    }

    // MARK: - Sign-in and usernames

    private func signIn(password raw: Any?) -> Reply {
        let password = string(raw)
        if let problem = passwordProblem(password) { return failure(400, problem) }
        guard let user = users.values.first(where: { $0.password == password }) else {
            return reply(["status": "new"])
        }
        return session(user, status: "signedIn")
    }

    private func register(_ input: [String: Any]) -> Reply {
        let password = string(input["password"])
        if let problem = passwordProblem(password) { return failure(400, problem) }
        guard let jpeg = Data(base64Encoded: string(input["photo"])), isJPEG(jpeg) else {
            return failure(400, "Нужна картинка в формате JPEG")
        }
        let caption = cleanCaption(input["caption"] as? String)
        // Someone made this password a moment ago: that is a sign-in, and the photo goes there.
        if let existing = users.values.first(where: { $0.password == password }) {
            _ = publish(author: existing.id, jpeg: jpeg, caption: caption)
            return session(existing, status: "signedIn")
        }
        let user = User(id: UUID().uuidString.lowercased(), username: nil, password: password)
        users[user.id] = user
        _ = publish(author: user.id, jpeg: jpeg, caption: caption)
        return session(user, status: "created")
    }

    private func session(_ user: User, status: String) -> Reply {
        currentUserId = user.id
        var body = meJSON(user)
        body["status"] = status
        body["token"] = "demo-\(user.id)"
        return reply(body)
    }

    private func passwordProblem(_ password: String) -> String? {
        let length = password.precomposedStringWithCanonicalMapping.unicodeScalars.count
        if length < 4 { return "Пароль — минимум 4 символа" }
        if length > 64 { return "Пароль — не длиннее 64 символов" }
        return nil
    }

    private static let words: [(kind: String, list: [String])] = [
        ("animal", ["барсук", "ёжик", "енот", "лиса", "сова", "бобр", "выдра", "хорёк", "лось", "капибара", "хомяк", "тюлень"]),
        ("swear", ["хуйло", "пиздюк", "ебанат", "мудак", "мудила", "залупа", "долбоёб", "жопа", "говнюк", "засранец"]),
        ("name", ["ярослава", "святослав", "мирослава", "богдан", "всеволод", "людмила", "добрыня", "забава", "любава", "злата"]),
    ]

    private func suggestions() -> [[String: Any]] {
        var offered = Set<String>()
        return Self.words.map { group in
            var pick = ""
            for attempt in 0..<60 {
                let word = group.list.randomElement() ?? group.list[0]
                let candidate = attempt < 6 ? word : "\(word)\(Int.random(in: 2...99))"
                let key = usernameKey(candidate)
                if !offered.contains(key) && !isTaken(key) {
                    pick = candidate
                    break
                }
            }
            offered.insert(usernameKey(pick))
            return ["username": pick, "kind": group.kind]
        }
    }

    private func chooseUsername(_ me: User, _ raw: Any?) -> Reply {
        if me.username != nil { return failure(409, "Юзернейм уже выбран") }
        guard let username = canonicalUsername(string(raw)) else {
            return failure(400, "Такого юзернейма нет среди вариантов — выбери из предложенных")
        }
        if isTaken(usernameKey(username)) { return failure(409, "Этот юзернейм только что заняли — выбери другой") }
        users[me.id]?.username = username
        // So the demo feed is full right away.
        befriend(me.id, "u-yara")
        befriend(me.id, "u-ezh")
        requests.append(Request(from: "u-dobr", to: me.id, at: nowMs()))
        return reply(meJSON(users[me.id] ?? me))
    }

    /// A word from the lists plus nothing or 2–999, spelled as in the list.
    private func canonicalUsername(_ value: String) -> String? {
        let key = usernameKey(value)
        let digits = String(key.reversed().prefix { $0.isNumber }.reversed())
        let base = String(key.dropLast(digits.count))
        if !digits.isEmpty {
            guard let n = Int(digits), (2...999).contains(n), !digits.hasPrefix("0") else { return nil }
        }
        let all = Self.words.flatMap { $0.list }
        guard let word = all.first(where: { usernameKey($0) == base }) else { return nil }
        return word + digits
    }

    nonisolated private func usernameKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    private func isTaken(_ key: String) -> Bool {
        users.values.contains { user in
            guard let name = user.username else { return false }
            return usernameKey(name) == key
        }
    }

    // MARK: - Friends

    private func pairKey(_ a: String, _ b: String) -> String {
        a < b ? "\(a)|\(b)" : "\(b)|\(a)"
    }

    private func areFriends(_ a: String, _ b: String) -> Bool {
        friendships[pairKey(a, b)] != nil
    }

    private func friendIds(_ id: String) -> [String] {
        friendships.keys.compactMap { key -> String? in
            let ids = key.split(separator: "|").map(String.init)
            guard ids.count == 2, ids.contains(id) else { return nil }
            return ids[0] == id ? ids[1] : ids[0]
        }
    }

    private func befriend(_ a: String, _ b: String) {
        if friendships[pairKey(a, b)] == nil { friendships[pairKey(a, b)] = nowMs() }
        requests.removeAll { ($0.from == a && $0.to == b) || ($0.from == b && $0.to == a) }
    }

    private func sendRequest(from me: User, to otherId: String) -> Reply {
        guard let other = users[otherId], other.username != nil else { return failure(404, "Пользователь не найден") }
        if other.id == me.id { return failure(400, "Это ты") }
        if areFriends(me.id, other.id) { return reply(friendsJSON(me.id)) }
        if requests.contains(where: { $0.from == other.id && $0.to == me.id }) {
            befriend(me.id, other.id)
            return reply(friendsJSON(me.id))
        }
        if !requests.contains(where: { $0.from == me.id && $0.to == other.id }) {
            requests.append(Request(from: me.id, to: other.id, at: nowMs()))
            // Demo strangers say yes a few seconds later.
            events.append((Date().addingTimeInterval(5), .accept(stranger: other.id, user: me.id)))
        }
        return reply(friendsJSON(me.id))
    }

    private func friendsJSON(_ id: String) -> [String: Any] {
        let friends = friendIds(id).compactMap { users[$0] }
            .sorted { usernameKey($0.username ?? "") < usernameKey($1.username ?? "") }
            .map { ["id": $0.id, "username": $0.username ?? "", "since": friendships[pairKey(id, $0.id)] ?? 0] as [String: Any] }
        let incoming = requests.filter { $0.to == id }.sorted { $0.at > $1.at }
            .compactMap { r -> [String: Any]? in
                guard let user = users[r.from] else { return nil }
                return ["id": user.id, "username": user.username ?? "", "createdAt": r.at]
            }
        let outgoing = requests.filter { $0.from == id }.sorted { $0.at > $1.at }
            .compactMap { r -> [String: Any]? in
                guard let user = users[r.to] else { return nil }
                return ["id": user.id, "username": user.username ?? "", "createdAt": r.at]
            }
        return ["friends": friends, "incoming": incoming, "outgoing": outgoing]
    }

    private func search(_ raw: String, viewer: String) -> [[String: Any]] {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("@") { trimmed.removeFirst() }
        let key = usernameKey(trimmed)
        guard key.count >= 2 else { return [] }
        let found = users.values.filter { user in
            guard let name = user.username else { return false }
            return usernameKey(name).hasPrefix(key)
        }
        let sorted = found.sorted { a, b in
            let ka = usernameKey(a.username ?? ""), kb = usernameKey(b.username ?? "")
            if (ka == key) != (kb == key) { return ka == key }
            return ka < kb
        }
        return sorted.prefix(20).map { user in
            ["id": user.id, "username": user.username ?? "", "relation": relation(viewer, user.id)]
        }
    }

    private func relation(_ me: String, _ other: String) -> String {
        if me == other { return "self" }
        if areFriends(me, other) { return "friend" }
        if requests.contains(where: { $0.from == me && $0.to == other }) { return "outgoing" }
        if requests.contains(where: { $0.from == other && $0.to == me }) { return "incoming" }
        return "none"
    }

    // MARK: - Photos and the locked rule

    /// Open when its place among the author's photos of the week is below
    /// 1 + the viewer's own photos that week. Own photos are always open.
    private func isOpen(_ photo: Photo, for viewer: String) -> Bool {
        if photo.authorId == viewer { return true }
        let allowance = 1 + photos.filter { $0.authorId == viewer && $0.weekId == photo.weekId }.count
        return rank(photo) < allowance
    }

    private func rank(_ photo: Photo) -> Int {
        photos.filter {
            $0.authorId == photo.authorId && $0.weekId == photo.weekId
                && ($0.createdAt < photo.createdAt || ($0.createdAt == photo.createdAt && $0.seq < photo.seq))
        }.count
    }

    private func visiblePhoto(_ id: String, viewer: String) -> Photo? {
        guard let photo = photos.first(where: { $0.id == id }) else { return nil }
        return photo.authorId == viewer || areFriends(viewer, photo.authorId) ? photo : nil
    }

    private func feedPhotos(authors: [String], before: Double, limit: Int) -> [Photo] {
        let set = Set(authors)
        return photos
            .filter { set.contains($0.authorId) && $0.createdAt < before }
            .sorted { $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.seq > $1.seq }
            .prefix(limit)
            .map { $0 }
    }

    private func publish(author: String, jpeg: Data, caption: String?) -> (photo: Photo, unlocked: Int) {
        let allowanceBefore = 1 + photos.filter { $0.authorId == author && $0.weekId == currentWeek }.count
        let photo = addPhoto(author: author, week: currentWeek, caption: caption, at: nowMs(), jpeg: jpeg)
        var unlocked = 0
        for friend in friendIds(author) {
            let theirs = photos.filter { $0.authorId == friend && $0.weekId == currentWeek }.count
            if theirs > allowanceBefore { unlocked += 1 }
        }
        if areFriends(author, "u-yara") && author != "u-yara" {
            events.append((Date().addingTimeInterval(8), .rate(photoId: photo.id, by: "u-yara")))
        }
        return (photo, unlocked)
    }

    @discardableResult
    private func addPhoto(author: String, week: String, caption: String?, at: Double, jpeg: Data) -> Photo {
        seq += 1
        let id = UUID().uuidString.lowercased()
        let url = Self.mediaDirectory.appendingPathComponent("\(id).jpg")
        try? jpeg.write(to: url)
        let photo = Photo(id: id, authorId: author, weekId: week, caption: caption, url: url, createdAt: at, seq: seq)
        photos.append(photo)
        return photo
    }

    private func photoJSON(_ p: Photo, viewer: String) -> [String: Any] {
        let authorName = users[p.authorId]?.username ?? ""
        guard isOpen(p, for: viewer) else {
            return [
                "id": p.id, "authorId": p.authorId, "authorName": authorName, "createdAt": p.createdAt, "weekId": p.weekId,
                "locked": true, "caption": NSNull(), "imageUrl": NSNull(), "canReact": false,
                "counts": ["creative": 0, "funny": 0, "wild": 0],
                "stars": ["count": 0, "total": 0, "average": 0],
                "myStars": 0, "mine": [String](), "reactors": [[String: Any]](), "raters": [[String: Any]](),
            ]
        }
        let photoReactions = reactions.filter { $0.photoId == p.id }.sorted { $0.at < $1.at }
        let photoStars = stars.filter { $0.photoId == p.id }.sorted { $0.at < $1.at }
        var counts: [String: Int] = ["creative": 0, "funny": 0, "wild": 0]
        for r in photoReactions { counts[r.kind, default: 0] += 1 }
        let total = photoStars.reduce(0) { $0 + $1.value }
        let average = photoStars.isEmpty ? 0 : (Double(total) / Double(photoStars.count) * 10).rounded() / 10
        return [
            "id": p.id, "authorId": p.authorId, "authorName": authorName, "createdAt": p.createdAt, "weekId": p.weekId,
            "locked": false,
            "caption": p.caption.map { $0 as Any } ?? NSNull(),
            "imageUrl": p.url.absoluteString,
            "canReact": p.authorId != viewer && p.weekId == currentWeek,
            "counts": counts,
            "stars": ["count": photoStars.count, "total": total, "average": average] as [String: Any],
            "myStars": photoStars.first { $0.userId == viewer }?.value ?? 0,
            "mine": photoReactions.filter { $0.userId == viewer }.map(\.kind),
            "reactors": photoReactions.map { ["userId": $0.userId, "name": users[$0.userId]?.username ?? "", "kind": $0.kind] },
            "raters": photoStars.map { ["userId": $0.userId, "name": users[$0.userId]?.username ?? "", "stars": $0.value] as [String: Any] },
        ]
    }

    // MARK: - Ratings

    private func ratable(_ id: String, viewer: String) -> Result<Photo, DemoFailure> {
        guard let photo = visiblePhoto(id, viewer: viewer) else { return .failure(DemoFailure(404, "Фото не найдено")) }
        if photo.authorId == viewer { return .failure(DemoFailure(403, "Свои фото оценивать нельзя")) }
        if !isOpen(photo, for: viewer) { return .failure(DemoFailure(403, "Это фото закрыто — выложи своё, чтобы открыть")) }
        if photo.weekId != currentWeek { return .failure(DemoFailure(409, "Голосование за ту неделю уже закрыто")) }
        return .success(photo)
    }

    private func rateStars(_ id: String, viewer: String, value: Int, clearing: Bool) -> Reply {
        if !clearing && !(1...3).contains(value) { return failure(400, "Звёзд может быть от 1 до 3") }
        switch ratable(id, viewer: viewer) {
        case .failure(let error):
            return failure(error.status, error.message)
        case .success(let photo):
            setStars(photo.id, by: viewer, value: clearing ? 0 : value)
            return reply(["photo": photoJSON(photo, viewer: viewer)])
        }
    }

    private func react(_ id: String, viewer: String, kind: String, on: Bool) -> Reply {
        guard Self.kinds.contains(kind) else { return failure(400, "Неизвестная оценка") }
        switch ratable(id, viewer: viewer) {
        case .failure(let error):
            return failure(error.status, error.message)
        case .success(let photo):
            setReaction(photo.id, by: viewer, kind: kind, on: on)
            return reply(["photo": photoJSON(photo, viewer: viewer)])
        }
    }

    private func setStars(_ photoId: String, by userId: String, value: Int) {
        if let index = stars.firstIndex(where: { $0.photoId == photoId && $0.userId == userId }) {
            if value == 0 { stars.remove(at: index) } else { stars[index].value = value }
        } else if value > 0 {
            stars.append(Star(photoId: photoId, userId: userId, value: value, at: nowMs()))
        }
    }

    private func setReaction(_ photoId: String, by userId: String, kind: String, on: Bool) {
        let exists = reactions.contains { $0.photoId == photoId && $0.userId == userId && $0.kind == kind }
        if on && !exists {
            reactions.append(Reaction(photoId: photoId, userId: userId, kind: kind, at: nowMs()))
        } else if !on {
            reactions.removeAll { $0.photoId == photoId && $0.userId == userId && $0.kind == kind }
        }
    }

    // MARK: - Week results (computeStandings from server/src/awards.js)

    private struct Stat {
        let userId: String
        let name: String
        var points = 0, activity = 0, posts = 0, given = 0, stars = 0, creative = 0, funny = 0, wild = 0

        func value(_ key: String) -> Int {
            switch key {
            case "points": return points
            case "activity": return activity
            case "creative": return creative
            case "funny": return funny
            case "wild": return wild
            default: return 0
            }
        }
    }

    private struct Tally {
        var stars = 0, starCount = 0, creative = 0, funny = 0, wild = 0
        var reactions: Int { creative + funny + wild }
    }

    private func weekResults(viewer: String, weekId: String, closedAt: Double?) -> [String: Any] {
        let memberIds = [viewer] + friendIds(viewer)
        let circle = Set(memberIds)
        var stats: [String: Stat] = [:]
        for id in memberIds {
            stats[id] = Stat(userId: id, name: users[id]?.username ?? "")
        }
        let weekPhotos = photos.filter { p in
            p.weekId == weekId && (circle.contains(p.authorId)
                || stars.contains { $0.photoId == p.id && circle.contains($0.userId) }
                || reactions.contains { $0.photoId == p.id && circle.contains($0.userId) })
        }
        var tallies: [String: Tally] = [:]
        for p in weekPhotos {
            tallies[p.id] = Tally()
            if circle.contains(p.authorId) { stats[p.authorId]?.posts += 1 }
        }
        let authorOf = Dictionary(weekPhotos.map { ($0.id, $0.authorId) }, uniquingKeysWith: { first, _ in first })
        for r in reactions {
            guard let author = authorOf[r.photoId], r.userId != author else { continue }
            switch r.kind {
            case "creative": tallies[r.photoId]?.creative += 1; stats[author]?.creative += 1
            case "funny": tallies[r.photoId]?.funny += 1; stats[author]?.funny += 1
            default: tallies[r.photoId]?.wild += 1; stats[author]?.wild += 1
            }
            stats[r.userId]?.given += 1
        }
        for s in stars {
            guard let author = authorOf[s.photoId], s.userId != author else { continue }
            tallies[s.photoId]?.stars += s.value
            tallies[s.photoId]?.starCount += 1
            stats[author]?.stars += s.value
            stats[s.userId]?.given += 1
        }
        for id in Array(stats.keys) {
            guard var s = stats[id] else { continue }
            s.activity = 2 * min(s.posts, 14) + s.given
            s.points = s.stars + s.creative + s.funny + s.wild + s.activity
            stats[id] = s
        }
        let leaderboard = stats.values.sorted { a, b in
            if a.points != b.points { return a.points > b.points }
            if a.stars != b.stars { return a.stars > b.stars }
            if a.name != b.name { return a.name < b.name }
            return a.userId < b.userId
        }

        // Photo of the week: most stars; then more reactions; then the earlier one.
        var best: Photo?
        for p in weekPhotos where circle.contains(p.authorId) {
            guard let t = tallies[p.id], t.stars > 0 else { continue }
            guard let current = best, let ct = tallies[current.id] else { best = p; continue }
            if t.stars > ct.stars || (t.stars == ct.stars && (t.reactions > ct.reactions || (t.reactions == ct.reactions && p.createdAt < current.createdAt))) {
                best = p
            }
        }

        func leader(_ key: String) -> Any {
            var winner: Stat?
            for s in leaderboard where s.value(key) > 0 {
                if winner == nil || s.value(key) > (winner?.value(key) ?? 0) { winner = s }
            }
            guard let winner else { return NSNull() }
            return ["userId": winner.userId, "name": winner.name, "value": winner.value(key)] as [String: Any]
        }

        var bestJSON: Any = NSNull()
        if let best, let t = tallies[best.id] {
            bestJSON = [
                "photoId": best.id, "authorId": best.authorId, "authorName": users[best.authorId]?.username ?? "",
                "caption": best.caption.map { $0 as Any } ?? NSNull(), "imageUrl": best.url.absoluteString,
                "stars": t.stars, "starCount": t.starCount, "creative": t.creative, "funny": t.funny, "wild": t.wild,
            ] as [String: Any]
        }
        let isCurrent = weekId == currentWeek
        return [
            "weekId": weekId,
            "startsAt": isCurrent ? weekStart : weekStart - Self.week,
            "endsAt": isCurrent ? weekEnd : weekStart,
            "closedAt": closedAt.map { $0 as Any } ?? NSNull(),
            "photoCount": weekPhotos.filter { circle.contains($0.authorId) }.count,
            "leaderboard": leaderboard.map {
                ["userId": $0.userId, "name": $0.name, "points": $0.points, "activity": $0.activity, "posts": $0.posts,
                 "given": $0.given, "stars": $0.stars, "creative": $0.creative, "funny": $0.funny, "wild": $0.wild] as [String: Any]
            },
            "bestPhoto": bestJSON,
            "friendOfWeek": leader("points"),
            "favoriteFriend": favoriteFriend(weekId: weekId, circle: circle, order: leaderboard),
            "mostCreative": leader("creative"),
            "mostFunny": leader("funny"),
            "mostWild": leader("wild"),
            "mostActive": leader("activity"),
        ]
    }

    // MARK: - Scheduled demo events

    private func runDueEvents() {
        let now = Date()
        let due = events.filter { $0.due <= now }
        events.removeAll { $0.due <= now }
        for item in due {
            switch item.event {
            case .accept(let stranger, let user):
                if requests.contains(where: { $0.from == user && $0.to == stranger }) { befriend(user, stranger) }
            case .rate(let photoId, let by):
                guard let photo = photos.first(where: { $0.id == photoId }), areFriends(by, photo.authorId),
                      isOpen(photo, for: by) else { continue }
                setStars(photoId, by: by, value: 3)
                setReaction(photoId, by: by, kind: "funny", on: true)
            }
        }
    }

    // MARK: - Seed

    private static let week: Double = 7 * 24 * 3600 * 1000

    private func seedIfNeeded() {
        guard !seeded else { return }
        seeded = true
        try? FileManager.default.createDirectory(at: Self.mediaDirectory, withIntermediateDirectories: true)

        // The current week closes next Sunday 21:00 Moscow time.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600) ?? .current
        var match = DateComponents()
        match.weekday = 1
        match.hour = 21
        match.minute = 0
        match.second = 0
        let end = calendar.nextDate(after: Date(), matching: match, matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3 * 86_400)
        weekEnd = end.timeIntervalSince1970 * 1000
        weekStart = weekEnd - Self.week

        for (id, name, password) in [
            ("u-barsuk", "барсук", "1234"), ("u-yara", "ярослава", nil), ("u-ezh", "ёжик", nil), ("u-dobr", "добрыня", nil),
            ("u-kapi", "капибара", nil), ("u-mud", "мудила7", nil), ("u-lub", "любава", nil), ("u-bar7", "барсук7", nil),
        ] as [(String, String, String?)] {
            users[id] = User(id: id, username: name, password: password)
        }
        for (a, b) in [("u-barsuk", "u-yara"), ("u-barsuk", "u-ezh"), ("u-yara", "u-ezh"), ("u-yara", "u-dobr")] {
            friendships[pairKey(a, b)] = weekStart - Self.week
        }
        requests.append(Request(from: "u-dobr", to: "u-barsuk", at: nowMs() - 3_600_000))

        // Photos spread over the part of the week that has passed: older first.
        let now = nowMs()
        func current(_ fraction: Double) -> Double { weekStart + (now - weekStart) * fraction }
        func previous(_ fraction: Double) -> Double { weekStart - Self.week + Self.week * fraction }
        var seed: UInt64 = 1
        func art(_ scene: DemoArt.Scene) -> Data {
            seed += 1
            return DemoArt.jpeg(scene, seed: seed)
        }

        // Last week, for the history list.
        let oldYara = addPhoto(author: "u-yara", week: previousWeek, caption: "Первый снег", at: previous(0.3), jpeg: art(.hills))
        let oldEzh = addPhoto(author: "u-ezh", week: previousWeek, caption: nil, at: previous(0.5), jpeg: art(.sea))
        let oldBarsuk = addPhoto(author: "u-barsuk", week: previousWeek, caption: "Вечер", at: previous(0.7), jpeg: art(.night))
        rateSeed(oldYara, by: "u-ezh", stars: 3, kinds: ["creative"])
        rateSeed(oldYara, by: "u-barsuk", stars: 2, kinds: [])
        rateSeed(oldEzh, by: "u-yara", stars: 2, kinds: ["funny"])
        rateSeed(oldBarsuk, by: "u-yara", stars: 3, kinds: ["wild"])

        // This week. ярослава's third photo is locked for anyone who has posted once.
        let y1 = addPhoto(author: "u-yara", week: currentWeek, caption: "Закат с крыши", at: current(0.15), jpeg: art(.sunset))
        let e1 = addPhoto(author: "u-ezh", week: currentWeek, caption: nil, at: current(0.25), jpeg: art(.sea))
        let d1 = addPhoto(author: "u-dobr", week: currentWeek, caption: "Горы", at: current(0.3), jpeg: art(.hills))
        let b1 = addPhoto(author: "u-barsuk", week: currentWeek, caption: "Первое фото", at: current(0.4), jpeg: art(.night))
        let y2 = addPhoto(author: "u-yara", week: currentWeek, caption: "Кофе на балконе", at: current(0.55), jpeg: art(.coffee))
        addPhoto(author: "u-dobr", week: currentWeek, caption: nil, at: current(0.65), jpeg: art(.sunset))
        let y3 = addPhoto(author: "u-yara", week: currentWeek, caption: "Секрет", at: current(0.8), jpeg: art(.night))
        for (index, stranger) in ["u-kapi", "u-mud", "u-lub", "u-bar7"].enumerated() {
            let scene = DemoArt.Scene.allCases[index % DemoArt.Scene.allCases.count]
            addPhoto(author: stranger, week: currentWeek, caption: nil, at: current(0.2 + 0.15 * Double(index)), jpeg: art(scene))
        }
        rateSeed(y1, by: "u-ezh", stars: 3, kinds: ["creative"])
        rateSeed(y1, by: "u-barsuk", stars: 2, kinds: [])
        rateSeed(y1, by: "u-dobr", stars: 3, kinds: ["wild"])
        rateSeed(y2, by: "u-ezh", stars: 2, kinds: ["funny"])
        rateSeed(e1, by: "u-yara", stars: 3, kinds: ["funny"])
        rateSeed(d1, by: "u-yara", stars: 1, kinds: [])
        rateSeed(b1, by: "u-yara", stars: 2, kinds: ["wild"])
        rateSeed(y3, by: "u-dobr", stars: 3, kinds: ["funny"])
        seedDays()
        // Picks friends made in «Кто лучше?»: ярослава is this week's favourite, ёжик was last week's.
        for (who, left, right, pick, week) in [
            ("u-ezh", "u-yara", "u-barsuk", "left", currentWeek), ("u-dobr", "u-yara", "u-barsuk", "left", currentWeek),
            ("u-barsuk", "u-ezh", "u-yara", "right", currentWeek), ("u-yara", "u-ezh", "u-barsuk", "left", previousWeek),
            ("u-barsuk", "u-ezh", "u-yara", "left", previousWeek),
        ] {
            duels.append(DuelRecord(
                id: UUID().uuidString.lowercased(), userId: who, date: "", left: left, right: right,
                choice: pick, chosenId: pick == "left" ? left : right, weekId: week
            ))
        }
    }

    private func seedDays() {
        let samples: [(daysAgo: Int, stars: Int, reasons: [String], liked: [String])] = [
            (1, 4, ["fatigued"], []),
            (2, 5, [], ["conversation", "music"]),
            (3, 2, ["rude", "gps"], []),
            (5, 3, ["unchanged"], []),
        ]
        for sample in samples {
            let date = Calendar.current.date(byAdding: .day, value: -sample.daysAgo, to: Date()) ?? Date()
            let key = DayRating.key(for: date)
            days["u-barsuk", default: [:]][key] = [
                "date": key, "stars": sample.stars, "reasons": sample.reasons, "liked": sample.liked,
                "condition": NSNull(), "place": NSNull(), "updatedAt": date.timeIntervalSince1970 * 1000,
            ] as [String: Any]
        }
    }

    private func rateSeed(_ photo: Photo, by userId: String, stars value: Int, kinds: [String]) {
        setStars(photo.id, by: userId, value: value)
        for kind in kinds { setReaction(photo.id, by: userId, kind: kind, on: true) }
    }

    // MARK: - Helpers

    private struct DemoFailure: Error {
        let status: Int
        let message: String
        init(_ status: Int, _ message: String) {
            self.status = status
            self.message = message
        }
    }

    private static let mediaDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("locket-demo", isDirectory: true)
    }()

    private func nowMs() -> Double {
        Date().timeIntervalSince1970 * 1000
    }

    private func meJSON(_ user: User) -> [String: Any] {
        let friends = friendIds(user.id).compactMap { users[$0] }
            .sorted { usernameKey($0.username ?? "") < usernameKey($1.username ?? "") }
            .map { ["id": $0.id, "username": $0.username ?? ""] }
        return [
            "user": ["id": user.id, "username": user.username.map { $0 as Any } ?? NSNull()] as [String: Any],
            "friends": friends,
            "incomingRequests": requests.filter { $0.to == user.id }.count,
            "week": ["id": currentWeek, "startsAt": weekStart, "endsAt": weekEnd] as [String: Any],
        ]
    }

    private func isJPEG(_ data: Data) -> Bool {
        data.count >= 3 && data.starts(with: [0xFF, 0xD8, 0xFF])
    }

    private func cleanCaption(_ raw: String?) -> String? {
        let words = (raw ?? "").split(whereSeparator: { $0.isWhitespace })
        let text = String(words.joined(separator: " ").prefix(60))
        return text.isEmpty ? nil : text
    }

    private func string(_ value: Any?) -> String {
        value as? String ?? ""
    }

    private func int(_ value: Any?) -> Int {
        if let n = value as? Int { return n }
        if let s = value as? String, let n = Int(s) { return n }
        return 0
    }

    private func reply(_ object: [String: Any], status: Int = 200) -> Reply {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return (status, data)
    }

    private func failure(_ status: Int, _ message: String) -> Reply {
        reply(["error": message], status: status)
    }
}
