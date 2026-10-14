import Foundation

/// The one request the lock-screen buttons and the widget need: set or clear
/// a rating. Lives in Shared so it works outside the main app.
enum ReactionAPI {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Response: Decodable {
        struct Photo: Decodable { let mine: [ReactionKind] }
        let photo: Photo
    }

    private struct ErrorBody: Decodable { let error: String }

    /// Returns the viewer's ratings on the photo after the change.
    @discardableResult
    static func set(_ kind: ReactionKind, on: Bool, photoId: String) async throws -> [ReactionKind] {
        guard let token = TokenStore.token else { throw Failure(message: "Нужно войти в Locket.") }
        let url = AppConfig.apiBaseURL.appendingPathComponent("api/photos/\(photoId)/reactions/\(kind.rawValue)")
        var request = URLRequest(url: url)
        request.httpMethod = on ? "PUT" : "DELETE"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw Failure(message: message ?? "Сервер ответил ошибкой \(status).")
        }
        return try JSONDecoder().decode(Response.self, from: data).photo.mine
    }
}
