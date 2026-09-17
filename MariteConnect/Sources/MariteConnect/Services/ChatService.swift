import Foundation

/// Reads and posts Teams channel messages, and automatically opens a StaffTask
/// whenever a new message @mentions someone.
final class ChatService {
    private let graph: GraphClient
    private let taskService: TaskService
    private let pushNotificationService: PushNotificationService

    init(graph: GraphClient, taskService: TaskService, pushNotificationService: PushNotificationService) {
        self.graph = graph
        self.taskService = taskService
        self.pushNotificationService = pushNotificationService
    }

    /// Channels visible to the signed-in user: Graph only returns private channels
    /// the caller is a member of, so this list is already correctly scoped between
    /// "everyone" (standard) and "certain people only" (private) channels.
    func fetchChannels() async throws -> [Channel] {
        let response: ChannelListResponse = try await graph.get(
            "teams/\(AppConfig.staffTeamId)/channels",
            queryItems: [URLQueryItem(name: "$select", value: "id,displayName,description,membershipType")]
        )
        return response.value
    }

    /// Members of a channel, used to populate the @mention picker. For a private
    /// channel this is exactly the restricted membership list; for a standard
    /// channel it's effectively the whole team.
    func fetchMembers(channelId: String) async throws -> [GraphUser] {
        let response: ChannelMembersResponse = try await graph.get(
            "teams/\(AppConfig.staffTeamId)/channels/\(channelId)/members"
        )
        return response.value.map { GraphUser(id: $0.userId, displayName: $0.displayName, userIdentityType: nil) }
    }

    func fetchMessages(channelId: String) async throws -> [ChatMessage] {
        let response: MessageListResponse = try await graph.get(
            "teams/\(AppConfig.staffTeamId)/channels/\(channelId)/messages",
            queryItems: [URLQueryItem(name: "$top", value: "50")]
        )
        return response.value.sorted { $0.createdDateTime < $1.createdDateTime }
    }

    /// Sends a plain message with no confirmation requirement.
    func sendMessage(channelId: String, text: String) async throws {
        let payload = MessageComposer.plainMessage(text: text)
        let _: ChatMessage = try await graph.post("teams/\(AppConfig.staffTeamId)/channels/\(channelId)/messages", body: payload)
    }

    /// Sends a message that tags `assignee` and opens a matching StaffTask so the
    /// tag can't silently get lost — it stays "open" until the assignee confirms it.
    /// Also asks the backend to push a "you've been tagged" alert; if that call
    /// fails (e.g. no connectivity right after sending), the task itself still
    /// exists and will simply be found the next time the assignee opens the app.
    func sendTaskMessage(channelId: String, channelName: String, text: String, assignee: GraphUser, createdBy: GraphUser) async throws {
        let payload = MessageComposer.taskMessage(text: text, mentioning: assignee)
        let sent: ChatMessage = try await graph.post("teams/\(AppConfig.staffTeamId)/channels/\(channelId)/messages", body: payload)

        let taskItemId = try await taskService.createTask(
            channelId: channelId,
            channelName: channelName,
            messageId: sent.id,
            summary: text,
            assignee: assignee,
            createdBy: createdBy
        )

        try? await pushNotificationService.notifyTagged(
            assignedToId: assignee.id,
            channelId: channelId,
            channelName: channelName,
            messageId: sent.id,
            taskItemId: taskItemId,
            taskSummary: text
        )
    }
}

struct ChannelMembersResponse: Decodable {
    let value: [ChannelMember]
}

struct ChannelMember: Decodable {
    let userId: String
    let displayName: String
}
