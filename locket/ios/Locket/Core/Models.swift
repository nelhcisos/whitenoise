import Foundation

/// `username` is nil until the person picks one of the three suggestions.
struct User: Codable, Hashable {
    let id: String
    let username: String?
}

struct Friend: Codable, Hashable, Identifiable {
    let id: String
    let username: String
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
}

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

struct ReactionCounts: Codable, Hashable {
    var creative: Int
    var funny: Int
    var wild: Int

    subscript(kind: ReactionKind) -> Int {
        get {
            switch kind {
            case .creative: return creative
            case .funny: return funny
            case .wild: return wild
            }
        }
        set {
            switch kind {
            case .creative: creative = newValue
            case .funny: funny = newValue
            case .wild: wild = newValue
            }
        }
    }
}

struct StarSummary: Codable, Hashable {
    var count: Int
    var total: Int
    var average: Double
}

struct Reactor: Codable, Hashable {
    let userId: String
    let name: String
    let kind: ReactionKind
}

struct Rater: Codable, Hashable {
    let userId: String
    let name: String
    let stars: Int
}

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
    var counts: ReactionCounts
    var stars: StarSummary
    var myStars: Int
    var mine: [ReactionKind]
    var reactors: [Reactor]
    var raters: [Rater]

    var date: Date { Date(timeIntervalSince1970: createdAt / 1000) }

    /// Applies the viewer's new rating locally, keeping the totals consistent.
    mutating func apply(_ rating: MyRating) {
        for kind in ReactionKind.allCases {
            let was = mine.contains(kind), now = rating.mine.contains(kind)
            if was != now { counts[kind] = max(0, counts[kind] + (now ? 1 : -1)) }
        }
        if myStars != rating.myStars {
            stars.total += rating.myStars - myStars
            if myStars == 0 { stars.count += 1 }
            if rating.myStars == 0 { stars.count = max(0, stars.count - 1) }
            stars.average = stars.count > 0 ? Double(stars.total) / Double(stars.count) : 0
        }
        mine = rating.mine
        myStars = rating.myStars
    }
}

struct Standing: Codable, Hashable, Identifiable {
    let userId: String
    let name: String
    let points: Int
    let activity: Int
    let posts: Int
    let given: Int
    let stars: Int
    let creative: Int
    let funny: Int
    let wild: Int

    var id: String { userId }
}

struct Nominee: Codable, Hashable {
    let userId: String
    let name: String
    let value: Int
}

struct BestPhoto: Codable, Hashable {
    let photoId: String
    let authorId: String
    let authorName: String
    let caption: String?
    let imageUrl: URL
    let stars: Int
    let starCount: Int
    let creative: Int
    let funny: Int
    let wild: Int
}

struct WeekResults: Codable, Hashable, Identifiable {
    let weekId: String
    let startsAt: Double
    let endsAt: Double
    let closedAt: Double?
    let photoCount: Int?
    let leaderboard: [Standing]
    let bestPhoto: BestPhoto?
    let friendOfWeek: Nominee?
    /// «Кто лучше?»: the most picked friend. Who was picked least is never sent.
    let favoriteFriend: Nominee?
    let mostCreative: Nominee?
    let mostFunny: Nominee?
    let mostWild: Nominee?
    let mostActive: Nominee?

    var id: String { weekId }
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

    init(type: String, photoId: String? = nil, weekId: String? = nil, userId: String? = nil) {
        self.type = type
        self.photoId = photoId
        self.weekId = weekId
        self.userId = userId
    }

    init(_ userInfo: [AnyHashable: Any]) {
        type = userInfo["type"] as? String ?? ""
        photoId = userInfo["photoId"] as? String
        weekId = userInfo["weekId"] as? String
        userId = userInfo["userId"] as? String
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

    /// "11 очков", with a non-breaking space so the number never wraps away from its word.
    static func points(_ n: Int) -> String { "\(n)\(nbsp)\(plural(n, "очко", "очка", "очков"))" }
}
