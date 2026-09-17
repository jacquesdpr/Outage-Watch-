import SwiftUI

struct ChannelListView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    @ObservedObject private var pushManager = PushNotificationManager.shared
    @StateObject private var viewModel: ChannelListViewModel
    @State private var navPath = NavigationPath()

    init(services: AppServices) {
        _viewModel = StateObject(wrappedValue: ChannelListViewModel(chatService: services.chatService))
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            content
                .navigationTitle("Channels")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if let name = services.currentUser?.displayName {
                                Text(name)
                            }
                            Button("Sign Out", role: .destructive, action: signOut)
                        } label: {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                }
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
                .onChange(of: viewModel.channels) { _, _ in attemptDeepLink() }
                .onChange(of: deepLinkRouter.pendingChannelId) { _, _ in attemptDeepLink() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.channels.isEmpty {
            LoadingView()
        } else if let error = viewModel.errorMessage, viewModel.channels.isEmpty {
            EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load channels", message: error)
        } else if viewModel.channels.isEmpty {
            EmptyStateView(systemImage: "bubble.left.and.bubble.right", title: "No channels yet", message: "Channels created in the Marite Staff Team will show up here.")
        } else {
            List(viewModel.channels) { channel in
                NavigationLink(value: channel) {
                    ChannelRow(channel: channel)
                }
            }
            .navigationDestination(for: Channel.self) { channel in
                MessageThreadView(channel: channel, services: services)
            }
        }
    }

    /// Opens the channel named in a tapped push notification, once both the
    /// channel list has loaded and a deep link is pending — whichever arrives second.
    private func attemptDeepLink() {
        guard let channelId = deepLinkRouter.pendingChannelId,
              let channel = viewModel.channels.first(where: { $0.id == channelId }) else { return }
        navPath.append(channel)
        deepLinkRouter.pendingChannelId = nil
    }

    private func signOut() {
        Task {
            if let token = pushManager.deviceToken {
                try? await services.pushNotificationService.unregisterDevice(token: token)
            }
            authManager.signOut()
        }
    }
}

private struct ChannelRow: View {
    let channel: Channel

    var body: some View {
        HStack {
            Image(systemName: channel.membershipType.isRestricted ? "lock.fill" : "number")
                .foregroundStyle(channel.membershipType.isRestricted ? .orange : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.displayName).font(.body)
                if let description = channel.description, !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}
