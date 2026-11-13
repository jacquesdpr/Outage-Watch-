import Foundation

/// Calls the Anthropic API directly from the app — the one external service
/// this architecture deliberately allows. There's no backend to hide the API
/// key behind, so it lives in AppConfig.claudeAPIKey; see that file's doc
/// comment, and docs/ARCHITECTURE.md, for why that's an acceptable tradeoff
/// here and how to reduce its downside.
final class AssistantService {
    private let legalLibrary: LegalLibraryService
    private let session: URLSession

    init(legalLibrary: LegalLibraryService, session: URLSession = .shared) {
        self.legalLibrary = legalLibrary
        self.session = session
    }

    func ask(question: String, history: [AssistantMessage]) async throws -> (answer: String, citations: [AssistantCitation]) {
        let matches = try await legalLibrary.findRelevant(query: question)
        let documentContext = matches.isEmpty
            ? "No matching documents were found in the legal library for this question."
            : matches.map { "[Document: \($0.document.title)]\n\($0.excerpt)" }.joined(separator: "\n\n")

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(AppConfig.claudeAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let historyMessages: [[String: String]] = history.suffix(10).map { ["role": $0.role.rawValue, "content": $0.text] }
        let finalMessage: [String: String] = [
            "role": "user",
            "content": "Relevant source material:\n\n\(documentContext)\n\n---\n\nQuestion: \(question)"
        ]

        let body: [String: Any] = [
            "model": AppConfig.claudeModel,
            "max_tokens": 1024,
            "system": Self.systemPrompt,
            "messages": historyMessages + [finalMessage]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AssistantError.requestFailed(status: status, message: String(data: data, encoding: .utf8) ?? "Unknown error")
        }

        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        let answer = decoded.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        let citations = matches.map { AssistantCitation(documentTitle: $0.document.title, excerpt: $0.excerpt) }
        return (answer, citations)
    }

    private struct ClaudeResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
    }

    private static let systemPrompt = """
    You are the Marite Connect Sectional Title Assistant, used internally by Marite Property Administrators staff.

    You help staff interpret South Africa's Sectional Titles Schemes Management Act (STSMA) and its regulations, and CSOS (Community Schemes Ombud Service) adjudication orders, and you help them think through real scenarios at the schemes Marite administers (e.g. a trustee dispute, a levy dispute, a rule enforcement question, a conduct complaint).

    Ground every substantive claim in the provided document excerpts. When you rely on an excerpt, cite it by document title. If the excerpts don't cover the question, say so plainly and describe generally how the Act tends to approach that type of issue, clearly flagging that it's general guidance rather than a citation to a specific clause or order — never invent a section number or case reference.

    For a described scenario, structure your answer as:
    1. The likely legal/procedural issue at play
    2. What the Act or a relevant CSOS order says about it
    3. Concrete next steps Marite staff should take

    You are not a substitute for an attorney; say so if the scenario looks like it needs one (e.g. potential litigation, criminal conduct, large financial exposure).
    """
}

enum AssistantError: LocalizedError {
    case requestFailed(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let status, let message):
            return "Claude returned status \(status): \(message)"
        }
    }
}
