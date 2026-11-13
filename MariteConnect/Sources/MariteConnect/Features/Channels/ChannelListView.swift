import SwiftUI

struct ChannelListView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var cloudKit: CloudKitManager
    @StateObject private var viewModel: ChannelListViewModel
    @State private var showingNewChannel = false

    init(services: AppServices, currentUserRecordName: String) {
        _viewModel = StateObject(wrappedValue: ChannelListViewModel(chatService: services.chatService, currentUserRecordName: currentUserRecordName))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Channels")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingNewChannel = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
                .sheet(isPresented: $showingNewChannel) {
                    if let staff = cloudKit.currentStaff {
                        NewChannelView(chatService: services.chatService, staffDirectory: services.staffDirectory, currentStaff: staff) { _ in
                            Task { await viewModel.load() }
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.channels.isEmpty {
            LoadingView()
        } else if let error = viewModel.errorMessage, viewModel.channels.isEmpty {
            EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load channels", message: error)
        } else if viewModel.visibleChannels.isEmpty {
            EmptyStateView(systemImage: "bubble.left.and.bubble.right", title: "No channels yet", message: "Tap + to create the first one.")
        } else {
            List(viewModel.visibleChannels) { channel in
                NavigationLink(value: channel) {
                    ChannelRow(channel: channel)
                }
            }
            .navigationDestination(for: Channel.self) { channel in
                MessageThreadView(channel: channel, services: services)
            }
        }
    }
}

private struct ChannelRow: View {
    let channel: Channel

    var body: some View {
        HStack {
            Image(systemName: channel.isPrivate ? "lock.fill" : "number")
                .foregroundStyle(channel.isPrivate ? .orange : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name).font(.body)
                if !channel.channelDescription.isEmpty {
                    Text(channel.channelDescription).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}
