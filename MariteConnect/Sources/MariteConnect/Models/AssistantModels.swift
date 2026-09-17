import Foundation

/// One turn in the Sectional Title Assistant conversation, shown as a chat bubble.
struct AssistantMessage: Identifiable, Hashable {
    let id = UUID()
    let role: Role
    let text: String
    var citations: [AssistantCitation] = []

    enum Role: String {
        case user
        case assistant
    }
}

/// A source document the assistant grounded its answer in — surfaced so staff can
/// open the actual Act clause or CSOS order rather than just trusting the summary.
struct AssistantCitation: Identifiable, Hashable {
    let id = UUID()
    let documentTitle: String
    let webUrl: String
    let excerpt: String
}

// MARK: - Wire format for the Azure Function relay

struct AssistantRequestBody: Encodable {
    let question: String
    /// Recent turns, oldest first, so the relay can keep short conversational context.
    let history: [AssistantHistoryTurn]
}

struct AssistantHistoryTurn: Encodable {
    let role: String
    let text: String
}

struct AssistantResponseBody: Decodable {
    let answer: String
    let citations: [AssistantCitationWire]
}

struct AssistantCitationWire: Decodable {
    let documentTitle: String
    let webUrl: String
    let excerpt: String
}
