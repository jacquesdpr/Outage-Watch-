import CloudKit
import Foundation

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
