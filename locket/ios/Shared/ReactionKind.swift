import Foundation

/// The three ratings. Raw values match the server API.
enum ReactionKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case fire
    case creative
    case funny

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .fire: return "🔥"
        case .creative: return "🎨"
        case .funny: return "😂"
        }
    }

    var title: String {
        switch self {
        case .fire: return "Огонь"
        case .creative: return "Креативно"
        case .funny: return "Смешно"
        }
    }

    /// Identifier of the matching button on a push notification.
    var notificationActionID: String { "RATE_\(rawValue.uppercased())" }

    init?(notificationActionID: String) {
        guard let kind = ReactionKind.allCases.first(where: { $0.notificationActionID == notificationActionID }) else {
            return nil
        }
        self = kind
    }
}
