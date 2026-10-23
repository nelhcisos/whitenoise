import SwiftUI

// «Кто лучше?»: once a day, at a random moment, the server sends two friends and you
// pick one — on the lock screen, without opening the app. At the end of the week the
// most picked is announced; who was picked least stays a secret.

struct DuelPerson: Codable, Hashable, Identifiable {
    let id: String
    let username: String
}

struct Duel: Codable, Equatable, Identifiable {
    let id: String
    let date: String
    let left: DuelPerson
    let right: DuelPerson
    /// "left", "right", or nil until chosen.
    var choice: String?

    var chosen: DuelPerson? {
        switch choice {
        case "left": return left
        case "right": return right
        default: return nil
        }
    }
}

enum DuelPick: String {
    case left, right
}

/// Identifiers shared with server/src/push.js.
enum DuelID {
    static let category = "FRIEND_DUEL"
}

/// Sends the pick from the lock-screen card (the NotificationContent extension).
enum DuelAPI {
    private struct Response: Decodable { let duel: Duel }
    private struct ErrorBody: Decodable { let error: String }

    static func choose(duelId: String, pick: DuelPick) async throws -> Duel {
        if AppConfig.isDemo {
            throw ReactionAPI.Failure(message: "В демо выбор отсюда не сохраняется — нажми «Открыть Locket» и выбери в ленте.", canRetry: false)
        }
        guard let token = TokenStore.token else {
            throw ReactionAPI.Failure(message: "Открой Locket и войди — тогда выбор будет сохраняться отсюда.", canRetry: false)
        }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let id = duelId.addingPercentEncoding(withAllowedCharacters: allowed) ?? duelId
        var request = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent("api/duels/\(id)/choice"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["pick": pick.rawValue])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ReactionAPI.Failure(message: "Нет связи с сервером.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error {
                throw ReactionAPI.Failure(message: message, canRetry: status >= 500)
            }
            throw ReactionAPI.Failure(message: "Сервер не ответил (\(status)).")
        }
        return try JSONDecoder().decode(Response.self, from: data).duel
    }
}

/// The two friends side by side. Once chosen, the pick is marked and the other fades.
/// Draws no background of its own: it sits on the app's ground and on the system material alike.
struct DuelChoiceView: View {
    let duel: Duel
    var busy = false
    let choose: @MainActor (DuelPick) -> Void

    var body: some View {
        HStack(spacing: 12) {
            tile(duel.left, pick: .left)
            tile(duel.right, pick: .right)
        }
    }

    private func tile(_ person: DuelPerson, pick: DuelPick) -> some View {
        let chosen = duel.choice == pick.rawValue
        let faded = duel.choice != nil && !chosen
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return Button {
            choose(pick)
        } label: {
            VStack(spacing: 10) {
                Text(String(person.username.prefix(1)).uppercased())
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 56, height: 56)
                    .background(Palette.systemFill, in: Circle())
                    .accessibilityHidden(true)
                Text(person.username)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 132)
            .padding(.horizontal, 8)
            .background(chosen ? Palette.accentTint : Palette.systemFill, in: shape)
            .overlay(shape.strokeBorder(chosen ? Palette.accent : Color.clear, lineWidth: 1.5))
            .opacity(faded ? 0.45 : 1)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(duel.choice != nil || busy)
        .accessibilityLabel(person.username)
        .accessibilityHint(duel.choice == nil ? "Выбрать" : "")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
