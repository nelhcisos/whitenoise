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

    func request<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        json: [String: String]? = nil,
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> T {
        var components = URLComponents(url: AppConfig.apiBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query
            // URLComponents leaves "+" alone, but servers read it as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 30
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
            if status == 401 && !path.hasPrefix("api/auth/") { throw APIError.unauthorized }
            let message = (try? decoder.decode(ErrorBody.self, from: data))?.error
            throw APIError.server(message ?? "Ошибка сервера (\(status)).")
        }
        return try decoder.decode(T.self, from: data)
    }
}

extension APIClient {
    func login(email: String, password: String) async throws -> AuthResponse {
        try await request("POST", "api/auth/login", json: ["email": email, "password": password])
    }

    func register(name: String, email: String, password: String) async throws -> AuthResponse {
        try await request("POST", "api/auth/register", json: ["name": name, "email": email, "password": password])
    }

    func logout(deviceToken: String?) async throws {
        let _: OKResponse = try await request("POST", "api/auth/logout", json: deviceToken.map { ["deviceToken": $0] } ?? [:])
    }

    func me() async throws -> MeResponse {
        try await request("GET", "api/me")
    }

    func rename(_ name: String) async throws -> MeResponse {
        try await request("PATCH", "api/me", json: ["name": name])
    }

    func registerDevice(token: String, environment: String) async throws {
        let _: OKResponse = try await request("POST", "api/devices", json: ["token": token, "env": environment])
    }

    func createCircle(name: String) async throws -> MeResponse {
        try await request("POST", "api/circles", json: ["name": name])
    }

    func joinCircle(code: String) async throws -> MeResponse {
        try await request("POST", "api/circles/join", json: ["code": code])
    }

    func leaveCircle() async throws -> MeResponse {
        try await request("POST", "api/circles/leave")
    }

    func renameCircle(_ name: String) async throws -> MeResponse {
        try await request("PATCH", "api/circle", json: ["name": name])
    }

    func photos(before: Double? = nil) async throws -> [Photo] {
        let query = before.map { [URLQueryItem(name: "before", value: String(Int64($0)))] } ?? []
        let response: PhotosResponse = try await request("GET", "api/photos", query: query)
        return response.photos
    }

    func upload(jpeg: Data, caption: String) async throws -> Photo {
        let query = caption.isEmpty ? [] : [URLQueryItem(name: "caption", value: caption)]
        let response: PhotoResponse = try await request("POST", "api/photos", query: query, body: jpeg, contentType: "image/jpeg")
        return response.photo
    }

    /// 1–3 sets the rating, 0 clears it.
    func setStars(_ stars: Int, photoId: String) async throws -> Photo {
        let path = "api/photos/\(photoId)/stars"
        let response: PhotoResponse = stars == 0
            ? try await request("DELETE", path)
            : try await request("PUT", path, json: ["stars": String(stars)])
        return response.photo
    }

    func react(_ kind: ReactionKind, on: Bool, photoId: String) async throws -> Photo {
        let response: PhotoResponse = try await request(on ? "PUT" : "DELETE", "api/photos/\(photoId)/reactions/\(kind.rawValue)")
        return response.photo
    }

    func deletePhoto(id: String) async throws {
        let _: OKResponse = try await request("DELETE", "api/photos/\(id)")
    }

    func currentWeek() async throws -> WeekResults {
        try await request("GET", "api/week/current")
    }

    func weeks() async throws -> [WeekResults] {
        let response: WeeksResponse = try await request("GET", "api/weeks")
        return response.weeks
    }
}
