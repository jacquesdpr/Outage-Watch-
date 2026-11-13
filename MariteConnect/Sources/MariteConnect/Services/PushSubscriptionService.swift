import CloudKit
import Foundation

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
