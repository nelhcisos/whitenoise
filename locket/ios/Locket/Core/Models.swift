import Foundation

struct User: Codable, Hashable {
    let id: String
    let name: String
    let email: String?
}

struct FriendCircle: Codable, Hashable {
    let id: String
    let name: String
    let inviteCode: String
    let ownerId: String
}

struct Member: Codable, Hashable, Identifiable {
    let id: String
    let name: String
}

struct WeekInfo: Codable, Hashable {
    let id: String
    let startsAt: Double
    let endsAt: Double
}

struct MeResponse: Codable {
    let user: User
    let circle: FriendCircle?
    let members: [Member]
    let week: WeekInfo
}

struct AuthResponse: Decodable {
    let token: String
    let me: MeResponse

    private enum CodingKeys: String, CodingKey { case token }

    init(from decoder: Decoder) throws {
        token = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .token)
        me = try MeResponse(from: decoder)
    }
}

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
    let caption: String?
    let imageUrl: URL
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
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(.ru)
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }
}

struct PhotosResponse: Decodable { let photos: [Photo] }
struct PhotoResponse: Decodable { let photo: Photo }
struct WeeksResponse: Decodable { let weeks: [WeekResults] }
struct OKResponse: Decodable { let ok: Bool }

/// The parts of a push payload the app cares about.
struct PushInfo: Sendable {
    var type: String
    var photoId: String?
    var weekId: String?

    init(type: String, photoId: String? = nil, weekId: String? = nil) {
        self.type = type
        self.photoId = photoId
        self.weekId = weekId
    }

    init(_ userInfo: [AnyHashable: Any]) {
        type = userInfo["type"] as? String ?? ""
        photoId = userInfo["photoId"] as? String
        weekId = userInfo["weekId"] as? String
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

    static func points(_ n: Int) -> String { "\(n) \(plural(n, "очко", "очка", "очков"))" }
}
