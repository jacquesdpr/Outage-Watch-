import CloudKit
import Foundation

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
