import SwiftUI

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
