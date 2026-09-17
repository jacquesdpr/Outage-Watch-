import Foundation

/// Bridges a tapped push notification (handled in PushNotificationManager,
/// outside the SwiftUI view tree) to the channel list, which opens the right
/// channel once it sees a pending channel ID here. A shared singleton because
/// AppDelegate/UNUserNotificationCenterDelegate callbacks aren't part of the
/// SwiftUI environment.
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    @Published var pendingChannelId: String?

    private init() {}
}
