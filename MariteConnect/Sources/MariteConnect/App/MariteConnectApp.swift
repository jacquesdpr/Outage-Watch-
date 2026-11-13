import SwiftUI
import UIKit

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
