import SwiftUI

struct MessageThreadView: View {
    let channel: Channel

    @StateObject private var viewModel: MessageThreadViewModel

    init(channel: Channel, services: AppServices) {
        self.channel = channel
        _viewModel = StateObject(wrappedValue: MessageThreadViewModel(
            channel: channel,
            chatService: services.chatService,
            taskService: services.taskService,
            currentUser: services.currentUser
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.messages.isEmpty {
                LoadingView()
            } else if viewModel.messages.isEmpty {
                EmptyStateView(systemImage: "bubble.left", title: "No messages yet", message: "Be the first to post in #\(channel.displayName).")
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

            MessageComposerView(model: viewModel)
        }
        .navigationTitle(channel.displayName)
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
                    Text(message.createdDateTime, style: .time).font(.caption).foregroundStyle(.secondary)
                }
                Text(message.body.plainText)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                if !message.mentions.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        Text(needsConfirmation ? "Waiting on your confirmation" : "Tagged: \(message.mentions.map(\.mentionText).joined(separator: ", "))")
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

private extension MessageBody {
    /// Strips the `<at id="0">Name</at>` markup Graph uses for mentions so the
    /// bubble reads naturally; a production build might render this richly instead.
    var plainText: String {
        guard contentType == "html" else { return content }
        return content
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
