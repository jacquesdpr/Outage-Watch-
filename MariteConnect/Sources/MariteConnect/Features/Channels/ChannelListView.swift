import SwiftUI

struct ChannelListView: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var viewModel: ViewModelBox = ViewModelBox()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Channels")
                .task {
                    viewModel.bind(chatService: services.chatService)
                    await viewModel.model?.load()
                }
                .refreshable { await viewModel.model?.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let model = viewModel.model {
            if model.isLoading && model.channels.isEmpty {
                LoadingView()
            } else if let error = model.errorMessage, model.channels.isEmpty {
                EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load channels", message: error)
            } else if model.channels.isEmpty {
                EmptyStateView(systemImage: "bubble.left.and.bubble.right", title: "No channels yet", message: "Channels created in the Marite Staff Team will show up here.")
            } else {
                List(model.channels) { channel in
                    NavigationLink(value: channel) {
                        ChannelRow(channel: channel)
                    }
                }
                .navigationDestination(for: Channel.self) { channel in
                    MessageThreadView(channel: channel)
                }
            }
        } else {
            LoadingView()
        }
    }
}

/// Small indirection so the view model can be created once `services` is known,
/// while still being a single stable @StateObject for the view's lifetime.
@MainActor
private final class ViewModelBox: ObservableObject {
    @Published var model: ChannelListViewModel?

    func bind(chatService: ChatService) {
        guard model == nil else { return }
        model = ChannelListViewModel(chatService: chatService)
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
