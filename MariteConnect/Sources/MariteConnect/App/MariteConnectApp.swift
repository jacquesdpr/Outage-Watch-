import SwiftUI

@main
struct MariteConnectApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView(authManager: authManager)
                .environmentObject(authManager)
                .environmentObject(DeepLinkRouter.shared)
        }
    }
}

/// Switches between the sign-in screen and the main tab experience based on
/// auth state. `services` is built from the very same AuthManager instance the
/// rest of the app uses, so every Graph call shares one signed-in session.
struct RootView: View {
    @ObservedObject private var authManager: AuthManager
    @StateObject private var services: AppServices
    @ObservedObject private var pushManager = PushNotificationManager.shared

    init(authManager: AuthManager) {
        _authManager = ObservedObject(wrappedValue: authManager)
        _services = StateObject(wrappedValue: AppServices(authManager: authManager))
    }

    var body: some View {
        Group {
            if authManager.isSignedIn {
                RootTabView()
                    .environmentObject(services)
                    .task {
                        await services.loadCurrentUser()
                        await pushManager.requestAuthorizationAndRegister()
                    }
                    .onReceive(pushManager.$deviceToken.compactMap { $0 }) { token in
                        Task { try? await services.pushNotificationService.registerDevice(token: token) }
                    }
            } else {
                LoginView()
            }
        }
        .animation(.default, value: authManager.isSignedIn)
    }
}
