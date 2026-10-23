import Foundation

// «Оцени свой день, как поездку»: every evening a notification asks for 1–5 stars.
// Below five you say what got in the way; at five, what you liked most.
// Option ids match server/src/app.js (DAY_REASONS, DAY_HIGHLIGHTS).

/// What stopped today from being «your» day.
enum DayReason: String, CaseIterable, Codable, Identifiable, Hashable {
    case unchanged, distracted, awkward, odor, issues, reckless, noChance, fatigued, gps, rude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unchanged: return "Ничего не поменялось"
        case .distracted: return "Всё отвлекало"
        case .awkward: return "Было неловко"
        case .odor: return "Сильный запах"
        case .issues: return "Проблемы с бла-бла-бла"
        case .reckless: return "Безрассудство"
        case .noChance: return "Не было шанса"
        case .fatigued: return "Усталость"
        case .gps: return "Ошибка GPS: место — отстой"
        case .rude: return "Грубые люди"
        }
    }
}

/// What you liked most about a five-star day.
enum DayHighlight: String, CaseIterable, Codable, Identifiable, Hashable {
    case advice, polite, comfort, clean, conversation, music

    var id: String { rawValue }

    var title: String {
        switch self {
        case .advice: return "Полезный совет"
        case .polite: return "Вежливые люди"
        case .comfort: return "Зона комфорта"
        case .clean: return "Чистый салон"
        case .conversation: return "Хороший разговор"
        case .music: return "Приятная музыка"
        }
    }
}

/// What helps tomorrow after a weak day.
enum DaySolution: String, CaseIterable, Identifiable {
    case warmup, meditate, coldShower

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warmup: return "Разминка"
        case .meditate: return "Медитация"
        case .coldShower: return "Холодный душ"
        }
    }

    var hint: String {
        switch self {
        case .warmup: return "5\u{00A0}минут с утра, пока не проснулся окончательно"
        case .meditate: return "10\u{00A0}минут тишины и дыхания"
        case .coldShower: return "30\u{00A0}секунд холодной воды в конце"
        }
    }

    var symbol: String {
        switch self {
        case .warmup: return "figure.flexibility"
        case .meditate: return "figure.mind.and.body"
        case .coldShower: return "shower"
        }
    }
}

/// One rated day. `stars == 0` means not rated yet (never sent to the server).
struct DayRating: Codable, Equatable, Identifiable {
    var date: String
    var stars: Int
    var reasons: [DayReason]
    var liked: [DayHighlight]
    /// «В хорошей форме?» and «В хорошем месте?»: nil until answered.
    var condition: Bool?
    var place: Bool?
    var updatedAt: Double?

    var id: String { date }

    static func blank(_ date: String) -> DayRating {
        DayRating(date: date, stars: 0, reasons: [], liked: [], condition: nil, place: nil, updatedAt: nil)
    }

    /// The JSON body for PUT api/days/<date>. Only the half that matches the stars is sent.
    func body() -> Data {
        let object: [String: Any] = [
            "stars": stars,
            "reasons": stars < 5 ? reasons.map(\.rawValue) : [],
            "liked": stars == 5 ? liked.map(\.rawValue) : [],
            "condition": condition.map { $0 as Any } ?? NSNull(),
            "place": place.map { $0 as Any } ?? NSNull(),
        ]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    /// "2026-10-23" for the phone's own calendar day.
    static func key(for date: Date) -> String {
        keyFormatter.string(from: date)
    }

    static func date(of key: String) -> Date? {
        keyFormatter.date(from: key)
    }

    /// «четверг, 23 октября»
    static func title(of key: String) -> String {
        guard let date = date(of: key) else { return key }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "ru_RU")))
    }

    private static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// The evening notification. The app schedules it locally; the content extension answers it.
enum DayReminderID {
    static let category = "DAY_RATING"
    static let daily = "locket.day"
    static let test = "locket.day.test"
}
