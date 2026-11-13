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

/// A legal-library document the assistant grounded its answer in.
struct AssistantCitation: Identifiable, Hashable {
    let id = UUID()
    let documentTitle: String
    let excerpt: String
}
