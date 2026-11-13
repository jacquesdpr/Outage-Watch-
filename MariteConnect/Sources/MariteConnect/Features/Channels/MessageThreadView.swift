import SwiftUI

struct MessageThreadView: View {
    let channel: Channel

    @StateObject private var viewModel: MessageThreadViewModel
    private let staffDirectory: StaffDirectoryService

    init(channel: Channel, services: AppServices) {
        self.channel = channel
        self.staffDirectory = services.staffDirectory
        _viewModel = StateObject(wrappedValue: MessageThreadViewModel(
            channel: channel,
            chatService: services.chatService,
            taskService: services.taskService,
            currentStaff: services.cloudKit.currentStaff!
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.messages.isEmpty {
                LoadingView()
            } else if viewModel.messages.isEmpty {
                EmptyStateView(systemImage: "bubble.left", title: "No messages yet", message: "Be the first to post in #\(channel.name).")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message, needsConfirmation: viewModel.isConfirmable(message: message)) {
                                    Task { await viewModel.confirmDone(message: message) }
                                }
                                .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let last = viewModel.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }

            if let error = viewModel.errorMessage {
                ErrorBanner(message: error)
            }

            MessageComposerView(model: viewModel, channel: channel, staffDirectory: staffDirectory)
        }
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let needsConfirmation: Bool
    let onConfirm: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            InitialsAvatar(name: message.senderName)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.senderName).font(.subheadline.bold())
                    Text(message.createdAt, style: .time).font(.caption).foregroundStyle(.secondary)
                }
                Text(message.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                if let taggedName = message.taggedUserName {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        Text(needsConfirmation ? "Waiting on your confirmation" : "Tagged: \(taggedName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if needsConfirmation {
                        Button("Mark as Done", action: onConfirm)
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}
