import CloudKit
import Foundation

/// Reads and posts channel messages, and automatically opens a StaffTask
/// whenever a new message tags someone.
final class ChatService {
    private let manager: CloudKitManager
    private let taskService: TaskService

    init(manager: CloudKitManager, taskService: TaskService) {
        self.manager = manager
        self.taskService = taskService
    }

    /// All channels, newest-named-first is unnecessary here — alphabetical
    /// reads better for a channel list. Visibility (standard vs. private) is
    /// filtered by the caller using `Channel.isVisible(to:)`.
    func fetchChannels() async throws -> [Channel] {
        let query = CKQuery(recordType: RecordType.channel, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        let (matchResults, _) = try await manager.publicDatabase.records(matching: query)
        return matchResults.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return Channel(record: record)
        }
    }

    func createChannel(name: String, description: String, isPrivate: Bool, members: [Staff], createdBy: Staff) async throws -> Channel {
        let record = Channel.makeNewRecord(
            name: name,
            description: description,
            isPrivate: isPrivate,
            members: members.map(\.userRecordName),
            createdBy: createdBy
        )
        let saved = try await manager.publicDatabase.save(record)
        guard let channel = Channel(record: saved) else { throw CloudKitManagerError.malformedRecord }
        return channel
    }

    func fetchMessages(channelRecordName: String) async throws -> [ChatMessage] {
        let channelRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: channelRecordName), action: .none)
        let query = CKQuery(recordType: RecordType.message, predicate: NSPredicate(format: "channel == %@", channelRef))
        // "___createTime" is CloudKit's actual server-side key for the built-in
        // Creation Date metadata field — the Swift-side `creationDate` property
        // name on CKRecord does not work as a query/sort key.
        query.sortDescriptors = [NSSortDescriptor(key: "___createTime", ascending: true)]
        let (matchResults, _) = try await manager.publicDatabase.records(matching: query)
        return matchResults.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return ChatMessage(record: record)
        }
    }

    /// Sends a plain message with no confirmation requirement.
    func sendMessage(channelRecordName: String, text: String, sender: Staff) async throws {
        let record = ChatMessage.makeNewRecord(channelRecordName: channelRecordName, text: text, sender: sender, tagging: nil)
        _ = try await manager.publicDatabase.save(record)
    }

    /// Sends a message that tags `assignee` and opens a matching StaffTask —
    /// CloudKit's own push subscription (set up when `assignee` registered)
    /// takes care of alerting them, with nothing further for this method to do.
    func sendTaskMessage(channelRecordName: String, channelName: String, text: String, assignee: Staff, sender: Staff) async throws {
        let messageRecord = ChatMessage.makeNewRecord(channelRecordName: channelRecordName, text: text, sender: sender, tagging: assignee)
        let savedMessage = try await manager.publicDatabase.save(messageRecord)

        try await taskService.createTask(
            channelRecordName: channelRecordName,
            channelName: channelName,
            messageRecordName: savedMessage.recordID.recordName,
            summary: text,
            assignedTo: assignee,
            createdBy: sender
        )
    }
}
