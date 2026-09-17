import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var services: AppServices

    var body: some View {
        TabView {
            ChannelListView(services: services)
                .tabItem { Label("Channels", systemImage: "bubble.left.and.bubble.right.fill") }

            MyTasksView(services: services)
                .tabItem { Label("My Tasks", systemImage: "checkmark.circle.fill") }

            SharePointSearchView(services: services)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            SectionalTitleAssistantView(services: services)
                .tabItem { Label("Legal Assistant", systemImage: "building.columns.fill") }
        }
    }
}
