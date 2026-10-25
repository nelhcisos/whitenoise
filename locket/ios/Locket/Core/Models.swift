import Foundation

/// `username` is nil until the person picks one of the three suggestions.
struct User: Codable, Hashable {
    let id: String
    let username: String?
}

struct Friend: Codable, Hashable, Identifiable {
    let id: String
    let username: String
    /// "11-14"; sent with a wishlist.
    var birthday: String? = nil
}

struct WeekInfo: Codable, Hashable {
    let id: String
    let startsAt: Double
    let endsAt: Double
}

struct MeResponse: Codable {
    let user: User
    let friends: [Friend]
    let incomingRequests: Int
    let week: WeekInfo
    /// "11-14", or nil when not given.
    let birthday: String?
    /// True after a few of your own photos while no birthday is given (and not just put off).
    let askBirthday: Bool?
}

/// A birthday: the day and the month, never the year ("11-14" in the API).
struct Birthday: Hashable {
    let month: Int
    let day: Int

    init(month: Int, day: Int) {
        self.month = month
        self.day = day
    }

    init?(_ key: String?) {
        let parts = key?.split(separator: "-").compactMap { Int($0) } ?? []
        guard parts.count == 2, (1...12).contains(parts[0]), (1...Self.days(in: parts[0])).contains(parts[1]) else { return nil }
        self.init(month: parts[0], day: parts[1])
    }

    /// Month names as they follow a day: "14 ноября".
    static let months = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]

    /// 29 for February: a birthday may be on the 29th.
    static func days(in month: Int) -> Int {
        [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
    }

    /// "14 ноября", with the number kept next to its month.
    var title: String { "\(day)\(nbsp)\(Self.months[month - 1])" }

    /// Days from `date` to the next one, on the phone's calendar; 0 on the day.
    /// In other years 29 February is celebrated on the 28th, like the server does.
    func daysLeft(from date: Date = Date()) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: today)
        for candidate in [year, year + 1] {
            let leap = (candidate % 4 == 0 && candidate % 100 != 0) || candidate % 400 == 0
            let shownDay = month == 2 && day == 29 && !leap ? 28 : day
            if let next = calendar.date(from: DateComponents(year: candidate, month: month, day: shownDay)), next >= today {
                return calendar.dateComponents([.day], from: today, to: next).day ?? 0
            }
        }
        return 0
    }

    /// Next to a friend's name: "Сегодня день рождения 🎂", "День рождения завтра",
    /// "День рождения через 5 дней" within a month, otherwise "День рождения 14 ноября".
    var friendLine: String {
        let left = daysLeft()
        switch left {
        case 0: return "Сегодня день рождения 🎂"
        case 1: return "День рождения завтра"
        case 2...30: return "День рождения через \(left)\(nbsp)\(Russian.plural(left, "день", "дня", "дней"))"
        default: return "День рождения \(title)"
        }
    }
}

/// POST api/auth/password and api/auth/register. `token`/`me` are present unless status == .new.
struct PasswordAuthResponse: Decodable {
    enum Status: String, Decodable {
        case signedIn, new, created
    }

    let status: Status
    let token: String?
    /// Decoded from the same JSON object as the token.
    let me: MeResponse?

    private enum CodingKeys: String, CodingKey { case status, token }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(Status.self, forKey: .status)
        let token = try container.decodeIfPresent(String.self, forKey: .token)
        self.token = token
        if token != nil {
            me = try MeResponse(from: decoder)
        } else {
            me = nil
        }
    }
}

struct UsernameSuggestion: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case animal, swear, name
    }

    let username: String
    let kind: Kind

    var id: String { username }
}

struct UsernameSuggestionsResponse: Decodable { let suggestions: [UsernameSuggestion] }

struct FriendEntry: Codable, Hashable, Identifiable {
    let id: String
    let username: String
    let since: Double
    /// How many wishes are in their wishlist.
    let wishCount: Int?
    /// "11-14", or nil when they haven't given it.
    let birthday: String?
}

/// One wish: what, where to get it (a web link) and a picture. Friends see it; only its owner deletes it.
struct Wish: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let url: URL?
    let imageUrl: URL?
    let createdAt: Double

    /// "ozon.ru": where the link leads, shown under the title.
    var site: String? {
        guard let host = url?.host(percentEncoded: false) else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

struct WishlistResponse: Decodable {
    let user: Friend
    let wishes: [Wish]
}

struct WishResponse: Decodable { let wish: Wish }

struct FriendRequest: Codable, Hashable, Identifiable {
    let id: String
    let username: String
    let createdAt: Double
}

/// GET api/friends and every friend action: the whole picture after the change.
struct FriendsResponse: Codable, Equatable {
    var friends: [FriendEntry]
    var incoming: [FriendRequest]
    var outgoing: [FriendRequest]
}

struct UserSearchResult: Codable, Hashable, Identifiable {
    enum Relation: String, Codable {
        case me = "self"
        case friend, outgoing, incoming, none
    }

    let id: String
    let username: String
    var relation: Relation
}

struct UsersResponse: Decodable { let users: [UserSearchResult] }

/// Ratings are blind: a photo carries only what *you* gave it, never totals or
/// who else rated. Winners are announced when the week closes (WeekResults).
struct Photo: Codable, Hashable, Identifiable {
    let id: String
    let authorId: String
    let authorName: String
    /// A friend's photo you haven't unlocked yet: no caption, no picture, nothing to rate.
    let locked: Bool
    let caption: String?
    let imageUrl: URL?
    let createdAt: Double
    let weekId: String
    var canReact: Bool
    var myStars: Int
    var mine: [ReactionKind]

    var date: Date { Date(timeIntervalSince1970: createdAt / 1000) }

    /// Applies the viewer's new rating locally.
    mutating func apply(_ rating: MyRating) {
        mine = rating.mine
        myStars = rating.myStars
    }
}

/// A winner: only the name, never a score.
struct Nominee: Codable, Hashable {
    let userId: String
    let name: String
}

/// A winning post. Its picture shows even to whoever had it locked: it's the prize.
struct BestPhoto: Codable, Hashable {
    let photoId: String
    let authorId: String
    let authorName: String
    let caption: String?
    let imageUrl: URL
}

/// «Пост дня»: the best post of one day of the week (`date` is "2026-10-14", Moscow time).
struct DayPost: Codable, Hashable, Identifiable {
    let date: String
    let photo: BestPhoto

    var id: String { date }
}

/// A closed week names its winners; the current week (closedAt == nil) has only
/// its dates and how many photos the circle posted — every winner field is nil.
struct WeekResults: Codable, Hashable, Identifiable {
    let weekId: String
    let startsAt: Double
    let endsAt: Double
    let closedAt: Double?
    let photoCount: Int?
    /// «Пост недели».
    let bestPhoto: BestPhoto?
    let mostCreativePost: BestPhoto?
    let mostFunnyPost: BestPhoto?
    let mostWildPost: BestPhoto?
    /// «Посты дня», oldest day first. Missing in weeks closed before it existed.
    let postsOfDay: [DayPost]?
    let friendOfWeek: Nominee?
    /// «Кто лучше?»: the most picked friend. Who was picked least is never sent.
    let favoriteFriend: Nominee?
    let mostCreative: Nominee?
    let mostFunny: Nominee?
    let mostWild: Nominee?
    let mostActive: Nominee?

    var id: String { weekId }
    var isClosed: Bool { closedAt != nil }
    var endDate: Date { Date(timeIntervalSince1970: endsAt / 1000) }

    /// "12 окт. – 18 окт." — nudged so a week ending Sunday 21:00 reads Monday–Sunday.
    var rangeTitle: String {
        let start = Date(timeIntervalSince1970: startsAt / 1000).addingTimeInterval(12 * 3600)
        let end = endDate.addingTimeInterval(-1)
        return "\(start.dayMonth) – \(end.dayMonth)"
    }
}

extension Date {
    /// "12 окт." with a non-breaking space, so the day never wraps away from its month.
    var dayMonth: String {
        formatted(.dateTime.day().month(.abbreviated).locale(.ru)).replacingOccurrences(of: " ", with: nbsp)
    }
}

struct PhotosResponse: Decodable { let photos: [Photo] }
struct PhotoResponse: Decodable { let photo: Photo }
/// `unlocked`: how many friends' photos of this week the post opened.
struct UploadResponse: Decodable {
    let photo: Photo
    let unlocked: Int
}
struct WeeksResponse: Decodable { let weeks: [WeekResults] }
struct DayResponse: Decodable { let day: DayRating }
struct DuelResponse: Decodable { let duel: Duel? }
struct DaysResponse: Decodable { let days: [DayRating] }
struct OKResponse: Decodable { let ok: Bool }

/// The parts of a push payload the app cares about.
struct PushInfo: Sendable {
    var type: String
    var photoId: String?
    var weekId: String?
    /// friend_request / friend_accepted: the other person.
    var userId: String?
    /// birthday: whose it is, to title their wishlist.
    var username: String?

    init(type: String, photoId: String? = nil, weekId: String? = nil, userId: String? = nil, username: String? = nil) {
        self.type = type
        self.photoId = photoId
        self.weekId = weekId
        self.userId = userId
        self.username = username
    }

    init(_ userInfo: [AnyHashable: Any]) {
        type = userInfo["type"] as? String ?? ""
        photoId = userInfo["photoId"] as? String
        weekId = userInfo["weekId"] as? String
        userId = userInfo["userId"] as? String
        username = userInfo["username"] as? String
    }
}

enum Russian {
    /// plural(5, "очко", "очка", "очков") → "очков"
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return one }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
        return many
    }
}
