import Foundation

/// Mirrors a Microsoft Teams channel. `membershipType` is what gives us the
/// "everyone" vs "certain people only" split for free: Teams standard channels are
/// visible to every team member, private channels only to the members explicitly
/// added to them.
struct Channel: Identifiable, Codable, Hashable {
    let id: String
    let displayName: String
    let description: String?
    let membershipType: MembershipType

    enum MembershipType: String, Codable {
        case standard
        case `private`
        case shared

        var isRestricted: Bool { self != .standard }
    }
}

struct ChannelListResponse: Decodable {
    let value: [Channel]
}
