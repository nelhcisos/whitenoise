import Foundation

/// Saves the day rating from the lock-screen card (the NotificationContent extension).
/// The app itself goes through APIClient; this is the extension's own small client.
enum DayAPI {
    private struct Response: Decodable { let day: DayRating }
    private struct ErrorBody: Decodable { let error: String }

    static func save(_ rating: DayRating) async throws -> DayRating {
        if AppConfig.isDemo {
            // The browser demo keeps its data inside the app, out of the extension's reach.
            throw ReactionAPI.Failure(message: "В демо оценка отсюда не сохраняется — нажми «Открыть Locket» и оцени день во вкладке «День».", canRetry: false)
        }
        guard let token = TokenStore.token else {
            throw ReactionAPI.Failure(message: "Открой Locket и войди — тогда оценки будут сохраняться отсюда.", canRetry: false)
        }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let date = rating.date.addingPercentEncoding(withAllowedCharacters: allowed) ?? rating.date
        var request = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent("api/days/\(date)"))
        request.httpMethod = "PUT"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = rating.body()

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
        return try JSONDecoder().decode(Response.self, from: data).day
    }
}
