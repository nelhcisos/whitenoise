import Foundation

/// Reactions given alongside the 1–3 star rating. Raw values match the server API.
enum ReactionKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case creative
    case funny
    case wild

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .creative: return "✍️"
        case .funny: return "😂"
        case .wild: return "🫪" // Emoji 17: shown by iOS 26.4 and newer
        }
    }

    var title: String {
        switch self {
        case .creative: return "Креатив"
        case .funny: return "Смешно"
        case .wild: return "Жесть"
        }
    }

    /// Weekly nomination for whoever collects the most of this reaction.
    var nomination: String {
        switch self {
        case .creative: return "Самый креативный"
        case .funny: return "Самый смешной"
        case .wild: return "Самый безбашенный"
        }
    }
}

enum Stars {
    static let max = 3
}
