import Foundation

/// CRUD against the "StaffTasks" SharePoint list, which is the single source of
/// truth for every tagged, must-be-confirmed task across all channels.
/// See docs/SETUP.md for the list's column schema.
final class TaskService {
    private let graph: GraphClient

    init(graph: GraphClient) {
        self.graph = graph
    }

    private var listItemsPath: String {
        "sites/\(AppConfig.siteId)/lists/\(AppConfig.staffTasksListName)/items"
    }

    /// All open tasks assigned to `userId`, newest first.
    func fetchMyOpenTasks(userId: String) async throws -> [StaffTask] {
        // $filter on list item fields requires the "fields/<Column>" prefix.
        let response: ListItemsResponse = try await graph.get(
            listItemsPath,
            queryItems: [
                URLQueryItem(name: "expand", value: "fields"),
                URLQueryItem(name: "$filter", value: "fields/AssignedToId eq '\(userId)' and fields/Status eq 'Open'"),
                URLQueryItem(name: "$orderby", value: "createdDateTime desc")
            ]
        )
        return response.value.map { StaffTask(itemId: $0.id, fields: $0.fields, createdDateTime: $0.createdDateTime) }
    }

    /// All tasks (any status) created by or assigned to the user, for a personal
    /// history view. Open tasks first, then completed ones.
    func fetchAllMyTasks(userId: String) async throws -> [StaffTask] {
        let response: ListItemsResponse = try await graph.get(
            listItemsPath,
            queryItems: [
                URLQueryItem(name: "expand", value: "fields"),
                URLQueryItem(name: "$filter", value: "fields/AssignedToId eq '\(userId)' or fields/CreatedById eq '\(userId)'"),
                URLQueryItem(name: "$orderby", value: "createdDateTime desc")
            ]
        )
        return response.value
            .map { StaffTask(itemId: $0.id, fields: $0.fields, createdDateTime: $0.createdDateTime) }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status { return lhs.status == .open }
                return lhs.createdDateTime > rhs.createdDateTime
            }
    }

    /// Returns the new list item's ID, so callers (e.g. ChatService, to trigger
    /// a push notification) can reference this specific task afterwards.
    @discardableResult
    func createTask(channelId: String, channelName: String, messageId: String, summary: String, assignee: GraphUser, createdBy: GraphUser) async throws -> String {
        let fields = StaffTaskFields(
            Title: summary,
            ChannelId: channelId,
            ChannelName: channelName,
            MessageId: messageId,
            AssignedToId: assignee.id,
            AssignedToName: assignee.displayName,
            CreatedById: createdBy.id,
            CreatedByName: createdBy.displayName,
            Status: StaffTask.Status.open.rawValue
        )
        let created: ListItem = try await graph.post(listItemsPath, body: NewListItem(fields: fields))
        return created.id
    }

    /// Marks a task done — this is what the "Done" button in a chat bubble or the
    /// My Tasks list calls.
    func markDone(itemId: String) async throws {
        try await graph.patch("\(listItemsPath)/\(itemId)/fields", body: StatusUpdate(Status: StaffTask.Status.done.rawValue))
    }

    func reopen(itemId: String) async throws {
        try await graph.patch("\(listItemsPath)/\(itemId)/fields", body: StatusUpdate(Status: StaffTask.Status.open.rawValue))
    }
}

private struct StatusUpdate: Encodable {
    let Status: String
}
