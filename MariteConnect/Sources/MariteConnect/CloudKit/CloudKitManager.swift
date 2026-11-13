import CloudKit
import Foundation

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
