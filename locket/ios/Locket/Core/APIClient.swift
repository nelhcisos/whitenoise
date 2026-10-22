import Foundation

enum APIError: LocalizedError, Equatable {
    case unauthorized
    case offline
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Сессия закончилась — войди заново."
        case .offline: return "Нет связи с сервером. Проверь интернет."
        case .server(let message): return message
        }
    }
}

/// Stateless apart from immutable helpers, so it's safe to share across tasks.
final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    private let decoder = JSONDecoder()
    private struct ErrorBody: Decodable { let error: String }

    /// `path` is already percent-encoded: constants plus `segment(_:)` for ids.
    func request<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        json: [String: String]? = nil,
        body: Data? = nil,
        contentType: String? = nil,
        timeout: TimeInterval = 30
    ) async throws -> T {
        var components = URLComponents(url: AppConfig.apiBaseURL, resolvingAgainstBaseURL: false)!
        var basePath = components.percentEncodedPath
        if basePath.hasSuffix("/") { basePath.removeLast() }
        components.percentEncodedPath = basePath + "/" + path
        if !query.isEmpty {
            components.queryItems = query
            // URLComponents leaves "+" alone, but servers read it as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = timeout
        if let token = TokenStore.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.offline
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // A wrong password on api/auth/* is the server's own message, not a lapsed session.
            if status == 401 && !path.hasPrefix("api/auth/") { throw APIError.unauthorized }
            let message = (try? decoder.decode(ErrorBody.self, from: data))?.error
            throw APIError.server(message ?? "Сервер не ответил (\(status)). Попробуй ещё раз через минуту.")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.server("Сервер ответил непонятно. Обнови приложение или попробуй позже.")
        }
    }

    /// One path segment (an id), percent-encoded so it can't add segments or a query.
    func segment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

extension APIClient {
    // MARK: Sign-in

    func passwordAuth(_ password: String) async throws -> PasswordAuthResponse {
        try await request("POST", "api/auth/password", json: ["password": password])
    }

    /// A new account comes with its first photo. The body is base64 of up to 8 MB, hence the longer timeout.
    func register(password: String, jpeg: Data, caption: String) async throws -> PasswordAuthResponse {
        try await request(
            "POST",
            "api/auth/register",
            json: ["password": password, "photo": jpeg.base64EncodedString(), "caption": caption],
            timeout: 60
        )
    }

    func logout(deviceToken: String?) async throws {
        let _: OKResponse = try await request("POST", "api/auth/logout", json: deviceToken.map { ["deviceToken": $0] } ?? [:])
    }

    // MARK: Profile

    func me() async throws -> MeResponse {
        try await request("GET", "api/me")
    }

    func usernameSuggestions() async throws -> [UsernameSuggestion] {
        let response: UsernameSuggestionsResponse = try await request("GET", "api/usernames/suggestions")
        return response.suggestions
    }

    func chooseUsername(_ username: String) async throws -> MeResponse {
        try await request("POST", "api/me/username", json: ["username": username])
    }

    func registerDevice(token: String, environment: String) async throws {
        let _: OKResponse = try await request("POST", "api/devices", json: ["token": token, "env": environment])
    }

    // MARK: Friends

    func searchUsers(_ query: String) async throws -> [UserSearchResult] {
        let response: UsersResponse = try await request("GET", "api/users/search", query: [URLQueryItem(name: "q", value: query)])
        return response.users
    }

    func friends() async throws -> FriendsResponse {
        try await request("GET", "api/friends")
    }

    func sendFriendRequest(userId: String) async throws -> FriendsResponse {
        try await request("POST", "api/friends/requests", json: ["userId": userId])
    }

    func acceptFriendRequest(userId: String) async throws -> FriendsResponse {
        try await request("POST", "api/friends/requests/\(segment(userId))/accept")
    }

    /// Declines an incoming request or cancels an outgoing one.
    func deleteFriendRequest(userId: String) async throws -> FriendsResponse {
        try await request("DELETE", "api/friends/requests/\(segment(userId))")
    }

    func removeFriend(userId: String) async throws -> FriendsResponse {
        try await request("DELETE", "api/friends/\(segment(userId))")
    }

    // MARK: Photos

    func photos(before: Double? = nil) async throws -> [Photo] {
        let query = before.map { [URLQueryItem(name: "before", value: String(Int64($0)))] } ?? []
        let response: PhotosResponse = try await request("GET", "api/photos", query: query)
        return response.photos
    }

    func upload(jpeg: Data, caption: String) async throws -> UploadResponse {
        let query = caption.isEmpty ? [] : [URLQueryItem(name: "caption", value: caption)]
        return try await request("POST", "api/photos", query: query, body: jpeg, contentType: "image/jpeg")
    }

    /// 1–3 sets the rating, 0 clears it.
    func setStars(_ stars: Int, photoId: String) async throws -> Photo {
        let path = "api/photos/\(segment(photoId))/stars"
        let response: PhotoResponse = stars == 0
            ? try await request("DELETE", path)
            : try await request("PUT", path, json: ["stars": String(stars)])
        return response.photo
    }

    func react(_ kind: ReactionKind, on: Bool, photoId: String) async throws -> Photo {
        let path = "api/photos/\(segment(photoId))/reactions/\(kind.rawValue)"
        let response: PhotoResponse = try await request(on ? "PUT" : "DELETE", path)
        return response.photo
    }

    func deletePhoto(id: String) async throws {
        let _: OKResponse = try await request("DELETE", "api/photos/\(segment(id))")
    }

    // MARK: Week

    func currentWeek() async throws -> WeekResults {
        try await request("GET", "api/week/current")
    }

    func weeks() async throws -> [WeekResults] {
        let response: WeeksResponse = try await request("GET", "api/weeks")
        return response.weeks
    }
}
