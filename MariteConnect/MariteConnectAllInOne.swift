// MariteConnectAllInOne.swift
//
// The ENTIRE Marite Connect app (CloudKit + Claude architecture) in one
// file, meant to be pasted into a single new Swift file in Xcode. This is
// the exact same code as the multi-file version in Sources/MariteConnect/ —
// just concatenated into one file for a quicker start. See
// PASTE_IN_XCODE.md in this same folder for the full, step-by-step setup
// (new project, enabling the iCloud/CloudKit and Push Notifications
// capabilities, creating the CloudKit schema) — none of that can be pasted
// as code, it's done through Xcode's and the CloudKit Dashboard's UI.
//
// Nothing in this file will do anything "real" until you:
//  1. Fill in AppConfig.claudeAPIKey and AppConfig.cloudKitContainerIdentifier below.
//  2. Create the CloudKit record types/fields described in docs/SETUP.md.
//  3. Enable the iCloud (CloudKit) and Push Notifications capabilities in Xcode.
// Until then, the app builds and runs, but iCloud setup will report an error.

import Foundation
import CloudKit
import PDFKit
import SwiftUI
import UIKit
import QuickLook
import UniformTypeIdentifiers

// MARK: - App/AppConfig.swift

/// Central place for app-wide configuration. Fill these in per docs/SETUP.md.
///
/// Unlike a typical backend-based app, `claudeAPIKey` genuinely is a secret
/// that ends up inside the shipped app binary — there is no server here to
/// hide it behind (that's the deliberate tradeoff of this architecture: no
/// backend to run, at the cost of the key being extractable by anyone who
/// gets the app's binary). That's an acceptable risk for an app you build,
/// sign, and hand only to Marite staff — never submit a build with a real
/// key to the public App Store. Mitigate the downside by setting a monthly
/// spending limit on the key at console.anthropic.com.
enum AppConfig {
    /// From console.anthropic.com → API Keys. Set a spending limit on this key.
    static let claudeAPIKey = "REPLACE_WITH_YOUR_ANTHROPIC_API_KEY"
    static let claudeModel = "claude-sonnet-5"

    /// Must match the iCloud container identifier in both the entitlements
    /// file and your Apple Developer / CloudKit Dashboard setup. See docs/SETUP.md.
    static let cloudKitContainerIdentifier = "iCloud.com.marite.MariteConnect"
}

// MARK: - CloudKit/CloudKitManager.swift

/// The app's one connection to CloudKit: account status, the signed-in
/// person's identity, and small generic helpers the services build on.
/// Everything lives in the **public** database — every staff member's app
/// reads and writes the same shared data, the same way everyone having a
/// Microsoft 365 tenant would share one Teams/SharePoint backend, except
/// here the "tenant" is just your CloudKit container and there's no admin
/// console to configure beyond the schema in docs/SETUP.md.
@MainActor
final class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()

    let container: CKContainer
    var publicDatabase: CKDatabase { container.publicCloudDatabase }

    @Published private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published private(set) var currentUserRecordName: String?
    @Published private(set) var currentStaff: Staff?
    @Published var errorMessage: String?

    private init() {
        container = CKContainer(identifier: AppConfig.cloudKitContainerIdentifier)
    }

    /// Call once at launch (and again after the person picks a display name
    /// for the first time). Resolves who's signed in and loads their Staff
    /// roster entry, creating nothing automatically — picking a name is a
    /// deliberate, visible step the first time (see StaffSetupView).
    func start() async {
        do {
            accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                errorMessage = Self.message(for: accountStatus)
                return
            }
            let userID = try await container.userRecordID()
            currentUserRecordName = userID.recordName
            currentStaff = try? await fetchStaff(userRecordName: userID.recordName)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchStaff(userRecordName: String) async throws -> Staff {
        let record = try await publicDatabase.record(for: Staff.recordID(forUserRecordName: userRecordName))
        guard let staff = Staff(record: record) else { throw CloudKitManagerError.malformedRecord }
        return staff
    }

    /// Saves this person's chosen display name and makes it the active
    /// identity for the rest of the app. Also (re)creates the push
    /// subscription that alerts them when someone tags them.
    func registerStaff(displayName: String) async throws {
        guard let userRecordName = currentUserRecordName else { throw CloudKitManagerError.notSignedIn }
        let staff = Staff(userRecordName: userRecordName, displayName: displayName)
        _ = try await publicDatabase.save(staff.makeRecord())
        currentStaff = staff
        try? await PushSubscriptionService(manager: self).ensureTaggedTaskSubscription(for: staff)
    }

    static func message(for status: CKAccountStatus) -> String {
        switch status {
        case .available: return ""
        case .noAccount: return "Sign in to iCloud in Settings to use Marite Connect."
        case .restricted: return "iCloud access is restricted on this device (parental controls or an MDM profile)."
        case .couldNotDetermine: return "Could not check your iCloud account. Check your connection and try again."
        case .temporarilyUnavailable: return "iCloud is temporarily unavailable. Try again shortly."
        @unknown default: return "iCloud is unavailable for an unknown reason."
        }
    }
}

enum CloudKitManagerError: LocalizedError {
    case notSignedIn
    case malformedRecord

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in to iCloud."
        case .malformedRecord: return "A CloudKit record was missing an expected field."
        }
    }
}

// MARK: - Models/CloudKitRecords.swift

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

// MARK: - Models/AssistantModels.swift

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

// MARK: - Services/StaffDirectoryService.swift

/// The staff roster: everyone who has opened the app and picked a display
/// name (see StaffSetupView). This is what the @mention picker and "add
/// members to a private channel" picker both read from — CloudKit has no
/// built-in "list my organization's other users" API the way Microsoft
/// Graph did, so the app keeps this small self-registered directory instead.
final class StaffDirectoryService {
    private let manager: CloudKitManager

    init(manager: CloudKitManager) {
        self.manager = manager
    }

    func fetchAll() async throws -> [Staff] {
        let query = CKQuery(recordType: RecordType.staff, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "displayName", ascending: true)]
        let (matchResults, _) = try await manager.publicDatabase.records(matching: query)
        return matchResults.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return Staff(record: record)
        }
    }
}

// MARK: - Services/PushSubscriptionService.swift

/// Sets up the one CloudKit subscription that makes "you've been tagged"
/// push notifications work with no server at all: CloudKit watches for new
/// StaffTask records assigned to this person and has Apple's own push
/// infrastructure deliver the alert, using the push capability already on
/// the app (no APNs key, no relay function, nothing to deploy).
final class PushSubscriptionService {
    private let manager: CloudKitManager

    init(manager: CloudKitManager) {
        self.manager = manager
    }

    /// Safe to call every launch: saving a subscription with the same ID
    /// updates it rather than creating a duplicate.
    func ensureTaggedTaskSubscription(for staff: Staff) async throws {
        let subscriptionID = "tagged-tasks-\(staff.userRecordName)"
        let predicate = NSPredicate(format: "assignedToUserRecordName == %@ AND status == %@", staff.userRecordName, StaffTask.Status.open.rawValue)
        let subscription = CKQuerySubscription(
            recordType: RecordType.staffTask,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.alertBody = "You've been tagged in Marite Connect — check My Tasks."
        notificationInfo.soundName = "default"
        notificationInfo.shouldBadge = true
        subscription.notificationInfo = notificationInfo

        _ = try await manager.publicDatabase.save(subscription)
    }
}

// MARK: - Services/ChatService.swift

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

// MARK: - Services/TaskService.swift

/// CRUD against StaffTask records, the single source of truth for every
/// tagged, must-be-confirmed task across all channels.
final class TaskService {
    private let manager: CloudKitManager

    init(manager: CloudKitManager) {
        self.manager = manager
    }

    @discardableResult
    func createTask(channelRecordName: String, channelName: String, messageRecordName: String, summary: String, assignedTo: Staff, createdBy: Staff) async throws -> StaffTask {
        let record = StaffTask.makeNewRecord(
            channelRecordName: channelRecordName,
            channelName: channelName,
            messageRecordName: messageRecordName,
            summary: summary,
            assignedTo: assignedTo,
            createdBy: createdBy
        )
        let saved = try await manager.publicDatabase.save(record)
        guard let task = StaffTask(record: saved) else { throw CloudKitManagerError.malformedRecord }
        return task
    }

    /// All tasks (any status) created by or assigned to this person, for the
    /// My Tasks tab. CloudKit's query predicates don't support OR across two
    /// different fields in the public database as cleanly as a single
    /// compound predicate for every case, so this runs two queries and merges.
    func fetchAllMyTasks(userRecordName: String) async throws -> [StaffTask] {
        async let assigned = fetchTasks(predicate: NSPredicate(format: "assignedToUserRecordName == %@", userRecordName))
        async let created = fetchTasks(predicate: NSPredicate(format: "createdByUserRecordName == %@", userRecordName))
        var byID: [String: StaffTask] = [:]
        for task in try await assigned + created {
            byID[task.id] = task
        }
        return byID.values.sorted { lhs, rhs in
            if lhs.status != rhs.status { return lhs.status == .open }
            return lhs.createdAt > rhs.createdAt
        }
    }

    func fetchOpenTasks(assignedToUserRecordName userRecordName: String) async throws -> [StaffTask] {
        try await fetchTasks(predicate: NSPredicate(format: "assignedToUserRecordName == %@ AND status == %@", userRecordName, StaffTask.Status.open.rawValue))
    }

    private func fetchTasks(predicate: NSPredicate) async throws -> [StaffTask] {
        let query = CKQuery(recordType: RecordType.staffTask, predicate: predicate)
        let (matchResults, _) = try await manager.publicDatabase.records(matching: query)
        return matchResults.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return StaffTask(record: record)
        }
    }

    func markDone(recordName: String) async throws {
        try await setStatus(.done, recordName: recordName)
    }

    func reopen(recordName: String) async throws {
        try await setStatus(.open, recordName: recordName)
    }

    private func setStatus(_ status: StaffTask.Status, recordName: String) async throws {
        let record = try await manager.publicDatabase.record(for: CKRecord.ID(recordName: recordName))
        record["status"] = status.rawValue
        _ = try await manager.publicDatabase.save(record)
    }
}

// MARK: - Services/LegalLibraryService.swift

/// A legal-library document plus the plain text PDFKit extracted from it,
/// kept in memory for the life of the app so repeated questions don't
/// re-parse the same PDF every time.
struct ExtractedLegalDocument {
    let document: LegalDocument
    let text: String
}

/// The Sectional Title Legal Library: the STSMA Act, its regulations, and
/// curated CSOS adjudication orders, stored as CKAssets so every staff
/// member's copy stays in sync automatically. Extraction and search both
/// happen entirely on-device via PDFKit — no server, no SharePoint, no
/// separate search index.
final class LegalLibraryService {
    private let manager: CloudKitManager
    private var textCache: [String: String] = [:]

    init(manager: CloudKitManager) {
        self.manager = manager
    }

    func fetchAll() async throws -> [LegalDocument] {
        let query = CKQuery(recordType: RecordType.legalDocument, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        let (matchResults, _) = try await manager.publicDatabase.records(matching: query)
        return matchResults.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return LegalDocument(record: record)
        }
    }

    func upload(title: String, localFileURL: URL, uploadedBy: Staff) async throws {
        let record = LegalDocument.makeNewRecord(title: title, localFileURL: localFileURL, uploadedBy: uploadedBy)
        _ = try await manager.publicDatabase.save(record)
    }

    /// Returns up to `maxDocuments` documents whose extracted text best
    /// matches `query`'s first keyword, each with a short excerpt — the same
    /// shape the legal assistant needs to ground its answer.
    func findRelevant(query: String, maxDocuments: Int = 4) async throws -> [(document: LegalDocument, excerpt: String)] {
        let documents = try await fetchAll()
        let keyword = query.split(separator: " ").first.map(String.init)?.lowercased() ?? ""

        var scored: [(LegalDocument, String, Int)] = []
        for document in documents {
            guard let text = extractedText(for: document) else { continue }
            let lowercased = text.lowercased()
            let score = keyword.isEmpty ? 0 : lowercased.components(separatedBy: keyword).count - 1
            let excerpt = buildExcerpt(from: text, keyword: keyword)
            scored.append((document, excerpt, score))
        }

        return scored
            .sorted { $0.2 > $1.2 }
            .prefix(maxDocuments)
            .map { ($0.0, $0.1) }
    }

    private func extractedText(for document: LegalDocument) -> String? {
        if let cached = textCache[document.id] { return cached }
        guard let fileURL = document.fileURL, let pdf = PDFDocument(url: fileURL) else { return nil }
        var text = ""
        for pageIndex in 0..<pdf.pageCount {
            text += pdf.page(at: pageIndex)?.string ?? ""
            text += " "
        }
        textCache[document.id] = text
        return text
    }

    private func buildExcerpt(from text: String, keyword: String, windowSize: Int = 1200) -> String {
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !keyword.isEmpty, let range = normalized.range(of: keyword, options: .caseInsensitive) else {
            return String(normalized.prefix(windowSize))
        }
        let start = normalized.index(range.lowerBound, offsetBy: -min(windowSize / 4, normalized.distance(from: normalized.startIndex, to: range.lowerBound)))
        let end = normalized.index(start, offsetBy: windowSize, limitedBy: normalized.endIndex) ?? normalized.endIndex
        return String(normalized[start..<end])
    }
}

// MARK: - Services/AssistantService.swift

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

// MARK: - Services/AppServices.swift

/// Wires up every service from the single shared CloudKitManager.
@MainActor
final class AppServices: ObservableObject {
    let cloudKit: CloudKitManager
    let staffDirectory: StaffDirectoryService
    let chatService: ChatService
    let taskService: TaskService
    let legalLibrary: LegalLibraryService
    let assistantService: AssistantService

    init(cloudKit: CloudKitManager) {
        self.cloudKit = cloudKit
        self.staffDirectory = StaffDirectoryService(manager: cloudKit)
        let taskService = TaskService(manager: cloudKit)
        self.taskService = taskService
        self.chatService = ChatService(manager: cloudKit, taskService: taskService)
        let legalLibrary = LegalLibraryService(manager: cloudKit)
        self.legalLibrary = legalLibrary
        self.assistantService = AssistantService(legalLibrary: legalLibrary)
    }
}

// MARK: - Common/CommonViews.swift

struct LoadingView: View {
    var body: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(.red, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
    }
}

struct InitialsAvatar: View {
    let name: String

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    var body: some View {
        Circle()
            .fill(Color.orange.gradient)
            .overlay(Text(initials).font(.caption.bold()).foregroundStyle(.white))
            .frame(width: 32, height: 32)
    }
}

// MARK: - Features/Setup/StaffSetupView.swift

struct StaffSetupView: View {
    @EnvironmentObject private var cloudKit: CloudKitManager
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                Text("Marite Connect")
                    .font(.largeTitle.bold())

                if let iCloudError = cloudKit.errorMessage, cloudKit.accountStatus != .available {
                    Text(iCloudError)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else {
                    Text("What should we call you? This is shown to colleagues\nwhen you post or get tagged.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            if cloudKit.accountStatus == .available {
                VStack(spacing: 12) {
                    TextField("Your name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, 32)

                    Button(action: save) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Continue").frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .padding(.horizontal, 32)
                }
            } else {
                Button("Try Again") {
                    Task { await cloudKit.start() }
                }
                .buttonStyle(.bordered)
            }

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red).padding(.horizontal, 32)
            }

            Spacer()
        }
        .padding()
        .task { await cloudKit.start() }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await cloudKit.registerStaff(displayName: name.trimmingCharacters(in: .whitespaces))
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Features/Channels/ChannelListViewModel.swift

@MainActor
final class ChannelListViewModel: ObservableObject {
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let chatService: ChatService
    private let currentUserRecordName: String

    init(chatService: ChatService, currentUserRecordName: String) {
        self.chatService = chatService
        self.currentUserRecordName = currentUserRecordName
    }

    /// Only channels this person should see: every standard channel, plus
    /// any private channel they're a listed member of.
    var visibleChannels: [Channel] {
        channels.filter { $0.isVisible(to: currentUserRecordName) }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            channels = try await chatService.fetchChannels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Features/Channels/NewChannelView.swift

struct NewChannelView: View {
    let chatService: ChatService
    let staffDirectory: StaffDirectoryService
    let currentStaff: Staff
    let onCreated: (Channel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var isPrivate = false
    @State private var allStaff: [Staff] = []
    @State private var selectedMembers: Set<String> = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Channel") {
                    TextField("Name (e.g. maintenance-requests)", text: $name)
                    TextField("Description (optional)", text: $description)
                    Toggle("Private — certain people only", isOn: $isPrivate)
                }

                if isPrivate {
                    Section("Members") {
                        if allStaff.isEmpty {
                            Text("No one else has opened the app yet.").foregroundStyle(.secondary)
                        }
                        ForEach(allStaff) { staff in
                            Button {
                                toggle(staff)
                            } label: {
                                HStack {
                                    InitialsAvatar(name: staff.displayName)
                                    Text(staff.displayName).foregroundStyle(.primary)
                                    Spacer()
                                    if selectedMembers.contains(staff.userRecordName) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("New Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .task {
                allStaff = (try? await staffDirectory.fetchAll())?.filter { $0.userRecordName != currentStaff.userRecordName } ?? []
            }
        }
    }

    private func toggle(_ staff: Staff) {
        if selectedMembers.contains(staff.userRecordName) {
            selectedMembers.remove(staff.userRecordName)
        } else {
            selectedMembers.insert(staff.userRecordName)
        }
    }

    private func create() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let members = allStaff.filter { selectedMembers.contains($0.userRecordName) }
                let channel = try await chatService.createChannel(
                    name: name.trimmingCharacters(in: .whitespaces),
                    description: description.trimmingCharacters(in: .whitespaces),
                    isPrivate: isPrivate,
                    members: isPrivate ? members + [currentStaff] : [],
                    createdBy: currentStaff
                )
                onCreated(channel)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Features/Channels/ChannelListView.swift

struct ChannelListView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var cloudKit: CloudKitManager
    @StateObject private var viewModel: ChannelListViewModel
    @State private var showingNewChannel = false

    init(services: AppServices, currentUserRecordName: String) {
        _viewModel = StateObject(wrappedValue: ChannelListViewModel(chatService: services.chatService, currentUserRecordName: currentUserRecordName))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Channels")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingNewChannel = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
                .sheet(isPresented: $showingNewChannel) {
                    if let staff = cloudKit.currentStaff {
                        NewChannelView(chatService: services.chatService, staffDirectory: services.staffDirectory, currentStaff: staff) { _ in
                            Task { await viewModel.load() }
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.channels.isEmpty {
            LoadingView()
        } else if let error = viewModel.errorMessage, viewModel.channels.isEmpty {
            EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load channels", message: error)
        } else if viewModel.visibleChannels.isEmpty {
            EmptyStateView(systemImage: "bubble.left.and.bubble.right", title: "No channels yet", message: "Tap + to create the first one.")
        } else {
            List(viewModel.visibleChannels) { channel in
                NavigationLink(value: channel) {
                    ChannelRow(channel: channel)
                }
            }
            .navigationDestination(for: Channel.self) { channel in
                MessageThreadView(channel: channel, services: services)
            }
        }
    }
}

private struct ChannelRow: View {
    let channel: Channel

    var body: some View {
        HStack {
            Image(systemName: channel.isPrivate ? "lock.fill" : "number")
                .foregroundStyle(channel.isPrivate ? .orange : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name).font(.body)
                if !channel.channelDescription.isEmpty {
                    Text(channel.channelDescription).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Features/Channels/MessageThreadViewModel.swift

@MainActor
final class MessageThreadViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var draft: String = ""
    @Published var mentionTarget: Staff?
    @Published private(set) var myOpenTaskMessageRecordNames: Set<String> = []

    let channel: Channel
    private let chatService: ChatService
    private let taskService: TaskService
    private let currentStaff: Staff

    init(channel: Channel, chatService: ChatService, taskService: TaskService, currentStaff: Staff) {
        self.channel = channel
        self.chatService = chatService
        self.taskService = taskService
        self.currentStaff = currentStaff
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let messagesTask = chatService.fetchMessages(channelRecordName: channel.recordName)
            async let tasksTask = taskService.fetchOpenTasks(assignedToUserRecordName: currentStaff.userRecordName)
            messages = try await messagesTask
            let myTasks = try await tasksTask
            myOpenTaskMessageRecordNames = Set(myTasks.filter { $0.channelRecordName == channel.recordName }.map(\.messageRecordName))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func send() async {
        guard canSend else { return }
        let text = draft
        let assignee = mentionTarget
        draft = ""
        mentionTarget = nil

        do {
            if let assignee {
                try await chatService.sendTaskMessage(channelRecordName: channel.recordName, channelName: channel.name, text: text, assignee: assignee, sender: currentStaff)
            } else {
                try await chatService.sendMessage(channelRecordName: channel.recordName, text: text, sender: currentStaff)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
            draft = text
            mentionTarget = assignee
        }
    }

    func isConfirmable(message: ChatMessage) -> Bool {
        message.taggedUserRecordName == currentStaff.userRecordName && myOpenTaskMessageRecordNames.contains(message.recordName)
    }

    func confirmDone(message: ChatMessage) async {
        do {
            let myTasks = try await taskService.fetchOpenTasks(assignedToUserRecordName: currentStaff.userRecordName)
            guard let task = myTasks.first(where: { $0.messageRecordName == message.recordName }) else { return }
            try await taskService.markDone(recordName: task.recordName)
            myOpenTaskMessageRecordNames.remove(message.recordName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Features/Channels/MessageThreadView.swift

struct MessageThreadView: View {
    let channel: Channel

    @StateObject private var viewModel: MessageThreadViewModel
    private let staffDirectory: StaffDirectoryService

    init(channel: Channel, services: AppServices) {
        self.channel = channel
        self.staffDirectory = services.staffDirectory
        _viewModel = StateObject(wrappedValue: MessageThreadViewModel(
            channel: channel,
            chatService: services.chatService,
            taskService: services.taskService,
            currentStaff: services.cloudKit.currentStaff!
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.messages.isEmpty {
                LoadingView()
            } else if viewModel.messages.isEmpty {
                EmptyStateView(systemImage: "bubble.left", title: "No messages yet", message: "Be the first to post in #\(channel.name).")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message, needsConfirmation: viewModel.isConfirmable(message: message)) {
                                    Task { await viewModel.confirmDone(message: message) }
                                }
                                .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let last = viewModel.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }

            if let error = viewModel.errorMessage {
                ErrorBanner(message: error)
            }

            MessageComposerView(model: viewModel, channel: channel, staffDirectory: staffDirectory)
        }
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let needsConfirmation: Bool
    let onConfirm: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            InitialsAvatar(name: message.senderName)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.senderName).font(.subheadline.bold())
                    Text(message.createdAt, style: .time).font(.caption).foregroundStyle(.secondary)
                }
                Text(message.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                if let taggedName = message.taggedUserName {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        Text(needsConfirmation ? "Waiting on your confirmation" : "Tagged: \(taggedName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if needsConfirmation {
                        Button("Mark as Done", action: onConfirm)
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}

// MARK: - Features/Channels/MessageComposerView.swift

struct MessageComposerView: View {
    @ObservedObject var model: MessageThreadViewModel
    let channel: Channel
    let staffDirectory: StaffDirectoryService

    @State private var showingMentionPicker = false
    @State private var candidates: [Staff] = []

    var body: some View {
        VStack(spacing: 6) {
            if let mentionTarget = model.mentionTarget {
                HStack {
                    Image(systemName: "at").foregroundStyle(.orange)
                    Text("Tagging \(mentionTarget.displayName) — they must confirm this is done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.mentionTarget = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    showingMentionPicker = true
                } label: {
                    Image(systemName: "at.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
                .accessibilityLabel("Tag someone")

                TextField("Message #\(channel.name)", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)

                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                }
                .disabled(!model.canSend)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 6)
        .background(.bar)
        .task {
            let all = (try? await staffDirectory.fetchAll()) ?? []
            candidates = channel.isPrivate ? all.filter { channel.memberUserRecordNames.contains($0.userRecordName) } : all
        }
        .sheet(isPresented: $showingMentionPicker) {
            MentionPickerView(members: candidates) { staff in
                model.mentionTarget = staff
                showingMentionPicker = false
            }
        }
    }
}

// MARK: - Features/Channels/MentionPickerView.swift

struct MentionPickerView: View {
    let members: [Staff]
    let onSelect: (Staff) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [Staff] {
        guard !query.isEmpty else { return members }
        return members.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { staff in
                Button {
                    onSelect(staff)
                } label: {
                    HStack {
                        InitialsAvatar(name: staff.displayName)
                        Text(staff.displayName).foregroundStyle(.primary)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search staff")
            .navigationTitle("Tag someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Features/Tasks/MyTasksViewModel.swift

@MainActor
final class MyTasksViewModel: ObservableObject {
    @Published private(set) var tasks: [StaffTask] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let taskService: TaskService
    private let currentStaff: Staff

    init(taskService: TaskService, currentStaff: Staff) {
        self.taskService = taskService
        self.currentStaff = currentStaff
    }

    var openCount: Int { tasks.filter { $0.status == .open }.count }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            tasks = try await taskService.fetchAllMyTasks(userRecordName: currentStaff.userRecordName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggle(_ task: StaffTask) async {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let newStatus: StaffTask.Status = task.status == .open ? .done : .open
        do {
            if newStatus == .done {
                try await taskService.markDone(recordName: task.recordName)
            } else {
                try await taskService.reopen(recordName: task.recordName)
            }
            tasks[index].status = newStatus
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Features/Tasks/MyTasksView.swift

struct MyTasksView: View {
    @StateObject private var viewModel: MyTasksViewModel

    init(services: AppServices) {
        _viewModel = StateObject(wrappedValue: MyTasksViewModel(taskService: services.taskService, currentStaff: services.cloudKit.currentStaff!))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("My Tasks")
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.tasks.isEmpty {
            LoadingView()
        } else if viewModel.tasks.isEmpty {
            EmptyStateView(systemImage: "checkmark.circle", title: "All clear", message: "Tasks tagged to you across every channel will show up here until you confirm them done.")
        } else {
            List {
                if viewModel.openCount > 0 {
                    Section("Open (\(viewModel.openCount))") {
                        ForEach(viewModel.tasks.filter { $0.status == .open }) { task in
                            TaskRow(task: task) { Task { await viewModel.toggle(task) } }
                        }
                    }
                }
                Section("Completed") {
                    ForEach(viewModel.tasks.filter { $0.status == .done }) { task in
                        TaskRow(task: task) { Task { await viewModel.toggle(task) } }
                    }
                }
            }
            if let error = viewModel.errorMessage {
                ErrorBanner(message: error)
            }
        }
    }
}

private struct TaskRow: View {
    let task: StaffTask
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.status == .done ? .green : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.summary)
                        .font(.body)
                        .strikethrough(task.status == .done)
                        .foregroundStyle(.primary)
                    Text("#\(task.channelName) · from \(task.createdByName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Features/Library/LegalLibraryViewModel.swift

@MainActor
final class LegalLibraryViewModel: ObservableObject {
    @Published private(set) var documents: [LegalDocument] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isUploading = false
    @Published var errorMessage: String?

    private let legalLibrary: LegalLibraryService
    private let currentStaff: Staff

    init(legalLibrary: LegalLibraryService, currentStaff: Staff) {
        self.legalLibrary = legalLibrary
        self.currentStaff = currentStaff
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            documents = try await legalLibrary.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// `pickedURL` is the security-scoped URL SwiftUI's fileImporter hands
    /// back; it's copied to a plain temporary file first because CKAsset
    /// needs a stable, non-security-scoped path to read from when saving.
    func upload(title: String, pickedURL: URL) async {
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        let didAccess = pickedURL.startAccessingSecurityScopedResource()
        defer { if didAccess { pickedURL.stopAccessingSecurityScopedResource() } }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
        do {
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            try FileManager.default.copyItem(at: pickedURL, to: tempURL)
            try await legalLibrary.upload(title: title, localFileURL: tempURL, uploadedBy: currentStaff)
            try? FileManager.default.removeItem(at: tempURL)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Features/Library/LegalLibraryView.swift

struct LegalLibraryView: View {
    @StateObject private var viewModel: LegalLibraryViewModel

    @State private var showingImporter = false
    @State private var pendingURL: URL?
    @State private var showingTitlePrompt = false
    @State private var pendingTitle = ""
    @State private var previewURL: URL?

    init(services: AppServices) {
        _viewModel = StateObject(wrappedValue: LegalLibraryViewModel(legalLibrary: services.legalLibrary, currentStaff: services.cloudKit.currentStaff!))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Legal Library")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingImporter = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(viewModel.isUploading)
                    }
                }
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
                .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf]) { result in
                    if case .success(let url) = result {
                        pendingURL = url
                        pendingTitle = url.deletingPathExtension().lastPathComponent
                        showingTitlePrompt = true
                    }
                }
                .alert("Name this document", isPresented: $showingTitlePrompt) {
                    TextField("Title", text: $pendingTitle)
                    Button("Cancel", role: .cancel) { pendingURL = nil }
                    Button("Add") {
                        if let url = pendingURL {
                            Task { await viewModel.upload(title: pendingTitle, pickedURL: url) }
                        }
                        pendingURL = nil
                    }
                } message: {
                    Text("This is shown as the citation title when the Legal Assistant references it.")
                }
                .quickLookPreview($previewURL)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.documents.isEmpty {
            LoadingView()
        } else if let error = viewModel.errorMessage, viewModel.documents.isEmpty {
            EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load the library", message: error)
        } else if viewModel.documents.isEmpty {
            EmptyStateView(systemImage: "doc.text.magnifyingglass", title: "No documents yet", message: "Tap + to add the STSMA Act, regulations, or a CSOS adjudication order (PDF).")
        } else {
            List(viewModel.documents) { document in
                Button {
                    previewURL = document.fileURL
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.title).foregroundStyle(.primary)
                        Text("Added by \(document.uploadedByName)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if viewModel.isUploading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Uploading…").foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Features/Assistant/SectionalTitleAssistantViewModel.swift

@MainActor
final class SectionalTitleAssistantViewModel: ObservableObject {
    @Published private(set) var messages: [AssistantMessage] = [
        AssistantMessage(
            role: .assistant,
            text: "Hi, I'm the Sectional Title Assistant. Ask me about the Sectional Titles Schemes Management Act, CSOS rulings, or describe a scenario at one of our schemes and I'll help you work out how to handle it — with citations to documents in the Legal Library where they apply."
        )
    ]
    @Published var draft = ""
    @Published private(set) var isThinking = false
    @Published var errorMessage: String?

    private let assistantService: AssistantService

    init(assistantService: AssistantService) {
        self.assistantService = assistantService
    }

    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking }

    func send() async {
        guard canSend else { return }
        let question = draft
        draft = ""
        errorMessage = nil
        messages.append(AssistantMessage(role: .user, text: question))

        isThinking = true
        defer { isThinking = false }
        do {
            let history = messages
            let (answer, citations) = try await assistantService.ask(question: question, history: history)
            messages.append(AssistantMessage(role: .assistant, text: answer, citations: citations))
        } catch {
            errorMessage = "Couldn't reach the Legal Assistant: \(error.localizedDescription)"
        }
    }
}

// MARK: - Features/Assistant/SectionalTitleAssistantView.swift

struct SectionalTitleAssistantView: View {
    @StateObject private var viewModel: SectionalTitleAssistantViewModel

    init(services: AppServices) {
        _viewModel = StateObject(wrappedValue: SectionalTitleAssistantViewModel(assistantService: services.assistantService))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(viewModel.messages) { message in
                                AssistantBubble(message: message).id(message.id)
                            }
                            if viewModel.isThinking {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Checking the Legal Library…").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let last = viewModel.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Ask a question or describe a scenario…", text: $viewModel.draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...6)
                    Button {
                        Task { await viewModel.send() }
                    } label: {
                        Image(systemName: "paperplane.fill").font(.title2)
                    }
                    .disabled(!viewModel.canSend)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Legal Assistant")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct AssistantBubble: View {
    let message: AssistantMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            Text(message.text)
                .padding(12)
                .background(message.role == .user ? Color.orange.opacity(0.15) : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            if !message.citations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(message.citations) { citation in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "doc.text.fill").font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(citation.documentTitle).font(.caption.bold())
                                Text(citation.excerpt).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

// MARK: - App/RootTabView.swift

struct RootTabView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var cloudKit: CloudKitManager

    var body: some View {
        TabView {
            ChannelListView(services: services, currentUserRecordName: cloudKit.currentStaff!.userRecordName)
                .tabItem { Label("Channels", systemImage: "bubble.left.and.bubble.right.fill") }

            MyTasksView(services: services)
                .tabItem { Label("My Tasks", systemImage: "checkmark.circle.fill") }

            LegalLibraryView(services: services)
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }

            SectionalTitleAssistantView(services: services)
                .tabItem { Label("Legal Assistant", systemImage: "building.columns.fill") }
        }
    }
}

// MARK: - App/MariteConnectApp.swift

@main
struct MariteConnectApp: App {
    @StateObject private var cloudKit = CloudKitManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(cloudKit)
        }
    }
}

/// Shows the name-setup screen until both iCloud is available and this
/// person has picked a display name, then switches to the main tabs.
/// `services` is built once that's true, so every view downstream can
/// assume `cloudKit.currentStaff` is non-nil.
struct RootView: View {
    @EnvironmentObject private var cloudKit: CloudKitManager
    @State private var services: AppServices?

    var body: some View {
        Group {
            if let services, cloudKit.currentStaff != nil {
                RootTabView()
                    .environmentObject(services)
            } else {
                StaffSetupView()
            }
        }
        .animation(.default, value: cloudKit.currentStaff != nil)
        .task {
            // Registering here (rather than needing a UIApplicationDelegate)
            // is enough for CloudKit's own push subscriptions to deliver —
            // CloudKit associates the device token with the container
            // automatically once the iCloud + Push Notifications
            // capabilities are both in place.
            UIApplication.shared.registerForRemoteNotifications()
            await cloudKit.start()
        }
        .onChange(of: cloudKit.currentStaff) { _, newValue in
            if newValue != nil, services == nil {
                services = AppServices(cloudKit: cloudKit)
            }
        }
    }
}

