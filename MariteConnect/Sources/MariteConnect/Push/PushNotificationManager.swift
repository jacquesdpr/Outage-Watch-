import Foundation
import UIKit
import UserNotifications

/// Requests notification permission, registers for APNs, and turns a tapped
/// "you've been tagged" notification into a deep link. A shared singleton
/// because APNs/UNUserNotificationCenter callbacks arrive through
/// AppDelegate, outside the SwiftUI view tree — views observe
/// `deviceToken` to know when to tell the backend about it.
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    @Published private(set) var deviceToken: String?

    private override init() {}

    func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        } catch {
            // Permission can always be granted later from iOS Settings; nothing to do here.
        }
    }

    func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        DispatchQueue.main.async {
            self.deviceToken = hex
        }
    }

    func didFailToRegister(error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    /// Show the alert even while the app is in the foreground, since a tagged
    /// task deserves attention whether or not you're already in the app.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let channelId = userInfo["channelId"] as? String else { return }
        await MainActor.run {
            DeepLinkRouter.shared.pendingChannelId = channelId
        }
    }
}
