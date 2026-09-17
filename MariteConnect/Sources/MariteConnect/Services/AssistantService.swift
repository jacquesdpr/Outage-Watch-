import Foundation

/// Talks to the serverless legal-assistant relay (ServerlessBackend/legal-assistant-function).
/// The app never calls Anthropic directly and never sees the API key — it just sends
/// the question plus short conversation history, authenticated with the user's own
/// Graph access token so the relay can confirm the caller is Marite staff.
final class AssistantService {
    private let authManager: AuthManager
    private let session: URLSession

    init(authManager: AuthManager, session: URLSession = .shared) {
        self.authManager = authManager
        self.session = session
    }

    func ask(question: String, history: [AssistantMessage]) async throws -> (answer: String, citations: [AssistantCitation]) {
        let token = try await authManager.acquireToken()

        var request = URLRequest(url: AppConfig.assistantEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body = AssistantRequestBody(
            question: question,
            history: history.suffix(10).map { AssistantHistoryTurn(role: $0.role.rawValue, text: $0.text) }
        )
        request.httpBody = try JSONEncoder.graph.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GraphError.invalidResponse
        }

        let decoded = try JSONDecoder.graph.decode(AssistantResponseBody.self, from: data)
        let citations = decoded.citations.map {
            AssistantCitation(documentTitle: $0.documentTitle, webUrl: $0.webUrl, excerpt: $0.excerpt)
        }
        return (decoded.answer, citations)
    }
}
