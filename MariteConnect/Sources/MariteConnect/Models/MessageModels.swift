import Foundation

/// A message in a Teams channel, as returned by
/// GET /teams/{id}/channels/{id}/messages
struct ChatMessage: Identifiable, Codable, Hashable {
    let id: String
    let createdDateTime: Date
    let from: MessageSender?
    let body: MessageBody
    let mentions: [ChatMention]

    var senderName: String { from?.user?.displayName ?? "Unknown" }
}

struct MessageSender: Codable, Hashable {
    let user: GraphUser?
}

struct GraphUser: Codable, Hashable {
    let id: String
    let displayName: String
    let userIdentityType: String?
}

struct MessageBody: Codable, Hashable {
    /// "html" or "text"
    let contentType: String
    let content: String
}

struct ChatMention: Codable, Hashable {
    let id: Int
    let mentionText: String
    let mentioned: MentionedIdentitySet
}

struct MentionedIdentitySet: Codable, Hashable {
    let user: GraphUser?
}

struct MessageListResponse: Decodable {
    let value: [ChatMessage]
}

/// Body used when posting a new message that @mentions one or more staff members.
/// Graph requires the mention markup (`<at id="0">Name</at>`) to appear inside the
/// HTML body, matched by index to the `mentions` array.
struct NewChatMessage: Encodable {
    let body: MessageBody
    let mentions: [ChatMention]?
}

enum MessageComposer {
    /// Builds the HTML body + mentions payload Graph expects for a message that
    /// tags one person and asks them to confirm completion.
    static func taskMessage(text: String, mentioning user: GraphUser) -> NewChatMessage {
        let html = "<at id=\"0\">\(user.displayName)</at> \(text.htmlEscaped)"
        let mention = ChatMention(id: 0, mentionText: user.displayName, mentioned: MentionedIdentitySet(user: user))
        return NewChatMessage(body: MessageBody(contentType: "html", content: html), mentions: [mention])
    }

    static func plainMessage(text: String) -> NewChatMessage {
        NewChatMessage(body: MessageBody(contentType: "text", content: text), mentions: nil)
    }
}

private extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
