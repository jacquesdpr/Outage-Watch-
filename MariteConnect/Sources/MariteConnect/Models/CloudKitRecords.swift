import CloudKit
import Foundation

/// CloudKit record type names, kept in one place so services and the
/// CloudKit Dashboard schema (see docs/SETUP.md) stay in sync.
enum RecordType {
    static let staff = "Staff"
    static let channel = "Channel"
    static let message = "Message"
    static let staffTask = "StaffTask"
    static let legalDocument = "LegalDocument"
}

/// One row in the staff roster. Every person registers themselves here (see
/// StaffDirectoryService) the first time they open the app, since CloudKit
/// has no Microsoft-Graph-style "list every coworker" API — this little
/// self-service directory is what the @mention picker reads from.
///
/// Its record name is derived from (but deliberately not equal to) the
/// user's own CloudKit user record name: CloudKit record IDs must be unique
/// per zone regardless of record type, and the system's own "Users" record
/// already occupies that exact name.
struct Staff: Identifiable, Hashable {
    let userRecordName: String
    var displayName: String

    var id: String { userRecordName }

    init(userRecordName: String, displayName: String) {
        self.userRecordName = userRecordName
        self.displayName = displayName
    }

    init?(record: CKRecord) {
        guard let displayName = record["displayName"] as? String,
              let userRecordName = record["userRecordName"] as? String else { return nil }
        self.userRecordName = userRecordName
        self.displayName = displayName
    }

    static func recordID(forUserRecordName userRecordName: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "Staff-\(userRecordName)")
    }

    func makeRecord() -> CKRecord {
        let record = CKRecord(recordType: RecordType.staff, recordID: Staff.recordID(forUserRecordName: userRecordName))
        record["userRecordName"] = userRecordName
        record["displayName"] = displayName
        return record
    }
}

/// Mirrors a chat channel. `isPrivate` + `memberUserRecordNames` give us the
/// "everyone" vs "certain people only" split: a standard channel is shown to
/// every staff member, a private one only to the people listed as members.
///
/// This enforcement happens in the app (the channel list only *shows* a
/// private channel to its members) rather than as a hard CloudKit per-record
/// permission — see docs/ARCHITECTURE.md for why, and how to harden it later
/// with CKShare if a channel ever needs to keep its contents genuinely
/// invisible to everyone else, not just hidden from the channel list.
struct Channel: Identifiable, Hashable {
    let recordName: String
    var name: String
    var channelDescription: String
    var isPrivate: Bool
    var memberUserRecordNames: [String]
    let createdByUserRecordName: String
    let createdByName: String

    var id: String { recordName }

    func isVisible(to userRecordName: String) -> Bool {
        !isPrivate || memberUserRecordNames.contains(userRecordName)
    }

    init?(record: CKRecord) {
        guard let name = record["name"] as? String,
              let createdByUserRecordName = record["createdByUserRecordName"] as? String,
              let createdByName = record["createdByName"] as? String else { return nil }
        self.recordName = record.recordID.recordName
        self.name = name
        self.channelDescription = record["channelDescription"] as? String ?? ""
        self.isPrivate = (record["isPrivate"] as? Int64 ?? 0) == 1
        self.memberUserRecordNames = record["memberUserRecordNames"] as? [String] ?? []
        self.createdByUserRecordName = createdByUserRecordName
        self.createdByName = createdByName
    }

    static func makeNewRecord(name: String, description: String, isPrivate: Bool, members: [String], createdBy: Staff) -> CKRecord {
        let record = CKRecord(recordType: RecordType.channel)
        record["name"] = name
        record["channelDescription"] = description
        record["isPrivate"] = isPrivate ? Int64(1) : Int64(0)
        record["memberUserRecordNames"] = isPrivate ? members : []
        record["createdByUserRecordName"] = createdBy.userRecordName
        record["createdByName"] = createdBy.displayName
        return record
    }
}

/// A message in a channel. `taggedUserRecordName` is set when the sender
/// @mentions someone — that's also what creates a matching StaffTask (see
/// ChatService.sendTaskMessage) so the tag can't get lost in scroll-back.
struct ChatMessage: Identifiable, Hashable {
    let recordName: String
    let channelRecordName: String
    let senderUserRecordName: String
    let senderName: String
    let text: String
    let createdAt: Date
    let taggedUserRecordName: String?
    let taggedUserName: String?

    var id: String { recordName }

    init?(record: CKRecord) {
        guard let channelRef = record["channel"] as? CKRecord.Reference,
              let senderUserRecordName = record["senderUserRecordName"] as? String,
              let senderName = record["senderName"] as? String,
              let text = record["text"] as? String,
              let createdAt = record.creationDate else { return nil }
        self.recordName = record.recordID.recordName
        self.channelRecordName = channelRef.recordID.recordName
        self.senderUserRecordName = senderUserRecordName
        self.senderName = senderName
        self.text = text
        self.createdAt = createdAt
        self.taggedUserRecordName = record["taggedUserRecordName"] as? String
        self.taggedUserName = record["taggedUserName"] as? String
    }

    static func makeNewRecord(channelRecordName: String, text: String, sender: Staff, tagging tagged: Staff?) -> CKRecord {
        let record = CKRecord(recordType: RecordType.message)
        let channelID = CKRecord.ID(recordName: channelRecordName)
        record["channel"] = CKRecord.Reference(recordID: channelID, action: .none)
        record["senderUserRecordName"] = sender.userRecordName
        record["senderName"] = sender.displayName
        record["text"] = text
        if let tagged {
            record["taggedUserRecordName"] = tagged.userRecordName
            record["taggedUserName"] = tagged.displayName
        }
        return record
    }
}

/// A tracked, must-be-confirmed task, created automatically whenever a
/// message tags someone. The single source of truth for "My Tasks" and for
/// the inline "Mark as Done" affordance under a tagged message.
struct StaffTask: Identifiable, Hashable {
    let recordName: String
    let channelRecordName: String
    let channelName: String
    let messageRecordName: String
    let summary: String
    let assignedToUserRecordName: String
    let assignedToName: String
    let createdByUserRecordName: String
    let createdByName: String
    let createdAt: Date
    var status: Status

    var id: String { recordName }

    enum Status: String {
        case open = "Open"
        case done = "Done"
    }

    init?(record: CKRecord) {
        guard let channelRecordName = record["channelRecordName"] as? String,
              let channelName = record["channelName"] as? String,
              let messageRecordName = record["messageRecordName"] as? String,
              let summary = record["summary"] as? String,
              let assignedToUserRecordName = record["assignedToUserRecordName"] as? String,
              let assignedToName = record["assignedToName"] as? String,
              let createdByUserRecordName = record["createdByUserRecordName"] as? String,
              let createdByName = record["createdByName"] as? String,
              let statusRaw = record["status"] as? String,
              let status = Status(rawValue: statusRaw),
              let createdAt = record.creationDate else { return nil }
        self.recordName = record.recordID.recordName
        self.channelRecordName = channelRecordName
        self.channelName = channelName
        self.messageRecordName = messageRecordName
        self.summary = summary
        self.assignedToUserRecordName = assignedToUserRecordName
        self.assignedToName = assignedToName
        self.createdByUserRecordName = createdByUserRecordName
        self.createdByName = createdByName
        self.createdAt = createdAt
        self.status = status
    }

    static func makeNewRecord(channelRecordName: String, channelName: String, messageRecordName: String, summary: String, assignedTo: Staff, createdBy: Staff) -> CKRecord {
        let record = CKRecord(recordType: RecordType.staffTask)
        record["channelRecordName"] = channelRecordName
        record["channelName"] = channelName
        record["messageRecordName"] = messageRecordName
        record["summary"] = summary
        record["assignedToUserRecordName"] = assignedTo.userRecordName
        record["assignedToName"] = assignedTo.displayName
        record["createdByUserRecordName"] = createdBy.userRecordName
        record["createdByName"] = createdBy.displayName
        record["status"] = Status.open.rawValue
        return record
    }
}

/// A document in the Sectional Title Legal Library (the STSMA Act, its
/// regulations, individual CSOS adjudication orders). Stored as a CKAsset —
/// CloudKit's way of syncing a file — so any staff member can add one from
/// their phone and everyone else's copy picks it up automatically, no
/// SharePoint or other document store required.
struct LegalDocument: Identifiable, Hashable {
    let recordName: String
    let title: String
    let fileURL: URL?
    let uploadedByName: String
    let uploadedAt: Date

    var id: String { recordName }

    init?(record: CKRecord) {
        guard let title = record["title"] as? String,
              let uploadedByName = record["uploadedByName"] as? String,
              let createdAt = record.creationDate else { return nil }
        self.recordName = record.recordID.recordName
        self.title = title
        self.uploadedByName = uploadedByName
        self.uploadedAt = createdAt
        self.fileURL = (record["file"] as? CKAsset)?.fileURL
    }

    static func makeNewRecord(title: String, localFileURL: URL, uploadedBy: Staff) -> CKRecord {
        let record = CKRecord(recordType: RecordType.legalDocument)
        record["title"] = title
        record["file"] = CKAsset(fileURL: localFileURL)
        record["uploadedByName"] = uploadedBy.displayName
        return record
    }
}
