import Foundation

/// A staff task, backed by a row in the "StaffTasks" SharePoint list (see
/// docs/SETUP.md for the list schema). Created automatically whenever a channel
/// message @mentions someone, so every tag has a trackable, confirmable item.
struct StaffTask: Identifiable, Hashable {
    let itemId: String
    let channelId: String
    let messageId: String
    let channelName: String
    let summary: String
    let assignedToId: String
    let assignedToName: String
    let createdById: String
    let createdByName: String
    let createdDateTime: Date
    var status: Status

    var id: String { itemId }

    enum Status: String, Codable {
        case open = "Open"
        case done = "Done"
    }
}

// MARK: - SharePoint list item wire format

/// SharePoint list items come back as `{ id, fields: { ... } }`.
struct ListItemsResponse: Decodable {
    let value: [ListItem]
}

struct ListItem: Decodable {
    let id: String
    let createdDateTime: Date
    let fields: StaffTaskFields
}

struct StaffTaskFields: Codable {
    let Title: String              // task summary, shown in the list UI
    let ChannelId: String
    let ChannelName: String
    let MessageId: String
    let AssignedToId: String
    let AssignedToName: String
    let CreatedById: String
    let CreatedByName: String
    let Status: String
}

struct NewListItem<Fields: Encodable>: Encodable {
    let fields: Fields
}

extension StaffTask {
    init(itemId: String, fields: StaffTaskFields, createdDateTime: Date) {
        self.itemId = itemId
        self.channelId = fields.ChannelId
        self.messageId = fields.MessageId
        self.channelName = fields.ChannelName
        self.summary = fields.Title
        self.assignedToId = fields.AssignedToId
        self.assignedToName = fields.AssignedToName
        self.createdById = fields.CreatedById
        self.createdByName = fields.CreatedByName
        self.createdDateTime = createdDateTime
        self.status = StaffTask.Status(rawValue: fields.Status) ?? .open
    }
}
