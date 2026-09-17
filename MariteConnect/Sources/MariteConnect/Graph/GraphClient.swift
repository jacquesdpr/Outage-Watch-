import Foundation

/// Thin async/await REST client for Microsoft Graph. Every call acquires a fresh
/// token from AuthManager (MSAL caches and silently refreshes it, so this is cheap).
final class GraphClient {
    private let authManager: AuthManager
    private let session: URLSession

    init(authManager: AuthManager, session: URLSession = .shared) {
        self.authManager = authManager
        self.session = session
    }

    func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        try await send(path: path, method: "GET", queryItems: queryItems, body: nil)
    }

    func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        try await send(path: path, method: "POST", queryItems: [], body: try JSONEncoder.graph.encode(body))
    }

    func patch<Body: Encodable>(_ path: String, body: Body) async throws {
        let _: EmptyResponse = try await send(path: path, method: "PATCH", queryItems: [], body: try JSONEncoder.graph.encode(body), allowEmptyBody: true)
    }

    /// Calls an absolute URL Graph itself returned (e.g. a `@odata.nextLink` or a
    /// `/search/query` POST target), rather than building the path ourselves.
    func postAbsolute<Body: Encodable, T: Decodable>(_ url: URL, body: Body) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.graph.encode(body)
        return try await perform(request)
    }

    private func send<T: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: Data?,
        allowEmptyBody: Bool = false
    ) async throws -> T {
        var components = URLComponents(url: AppConfig.graphBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else { throw GraphError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return try await perform(request, allowEmptyBody: allowEmptyBody)
    }

    private func perform<T: Decodable>(_ request: URLRequest, allowEmptyBody: Bool = false) async throws -> T {
        var request = request
        let token = try await authManager.acquireToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GraphError.invalidResponse }

        guard (200..<300).contains(http.statusCode) else {
            throw GraphError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        if allowEmptyBody, data.isEmpty, let empty = EmptyResponse() as? T {
            return empty
        }

        do {
            return try JSONDecoder.graph.decode(T.self, from: data)
        } catch {
            throw GraphError.decoding(error)
        }
    }
}

/// Used for PATCH/DELETE calls that return 204 No Content.
struct EmptyResponse: Decodable {}

extension JSONDecoder {
    static let graph: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension JSONEncoder {
    static let graph: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
