import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            ChannelListView()
                .tabItem { Label("Channels", systemImage: "bubble.left.and.bubble.right.fill") }

            MyTasksView()
                .tabItem { Label("My Tasks", systemImage: "checkmark.circle.fill") }

            SharePointSearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            SectionalTitleAssistantView()
                .tabItem { Label("Legal Assistant", systemImage: "building.columns.fill") }
        }
    }
}
