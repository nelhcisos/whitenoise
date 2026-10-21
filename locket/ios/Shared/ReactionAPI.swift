import Foundation

/// What the viewer has given a photo: 0–3 stars and a set of reactions.
struct MyRating: Decodable, Equatable {
    var myStars: Int
    var mine: [ReactionKind]
}

/// The two requests the lock-screen notification and the widget need.
/// Lives in Shared so it works outside the main app.
enum ReactionAPI {
    /// A failed request. The message says what happened; `canRetry` says whether
    /// tapping again can help (no connection, a server hiccup) or not (signed out).
    struct Failure: LocalizedError {
        let message: String
        var canRetry = true
        var errorDescription: String? { message }
    }

    private struct Response: Decodable { let photo: MyRating }
    private struct ErrorBody: Decodable { let error: String }

    static func setReaction(_ kind: ReactionKind, on: Bool, photoId: String) async throws -> MyRating {
        try await send(on ? "PUT" : "DELETE", "api/photos/\(photoId)/reactions/\(kind.rawValue)", body: nil)
    }

    /// 1–3 sets the rating, 0 clears it.
    static func setStars(_ stars: Int, photoId: String) async throws -> MyRating {
        if stars == 0 { return try await send("DELETE", "api/photos/\(photoId)/stars", body: nil) }
        return try await send("PUT", "api/photos/\(photoId)/stars", body: try JSONSerialization.data(withJSONObject: ["stars": stars]))
    }

    private static func send(_ method: String, _ path: String, body: Data?) async throws -> MyRating {
        guard let token = TokenStore.token else { throw Failure(message: "Открой Locket и войди — тогда оценки будут сохраняться отсюда.", canRetry: false) }
        var request = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure(message: "Нет связи с сервером.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error {
                // The server's own words (a deleted photo, a closed week): tapping again won't help.
                throw Failure(message: message, canRetry: status >= 500)
            }
            throw Failure(message: "Сервер не ответил (\(status)).")
        }
        return try JSONDecoder().decode(Response.self, from: data).photo
    }
}
