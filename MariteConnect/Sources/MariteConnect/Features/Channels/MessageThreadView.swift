import SwiftUI

struct MessageThreadView: View {
    let channel: Channel

    @EnvironmentObject private var services: AppServices
    @StateObject private var box = ViewModelBox()

    var body: some View {
        VStack(spacing: 0) {
            if let model = box.model {
                if model.isLoading && model.messages.isEmpty {
                    LoadingView()
                } else if model.messages.isEmpty {
                    EmptyStateView(systemImage: "bubble.left", title: "No messages yet", message: "Be the first to post in #\(channel.displayName).")
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(model.messages) { message in
                                    MessageBubble(message: message, needsConfirmation: model.isConfirmable(message: message)) {
                                        Task { await model.confirmDone(message: message) }
                                    }
                                    .id(message.id)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: model.messages.count) { _, _ in
                            if let last = model.messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }

                if let error = model.errorMessage {
                    ErrorBanner(message: error)
                }

                MessageComposerView(model: model)
            } else {
                LoadingView()
            }
        }
        .navigationTitle(channel.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            box.bind(channel: channel, services: services)
            await box.model?.load()
        }
    }
}

@MainActor
private final class ViewModelBox: ObservableObject {
    @Published var model: MessageThreadViewModel?

    func bind(channel: Channel, services: AppServices) {
        guard model == nil else { return }
        model = MessageThreadViewModel(
            channel: channel,
            chatService: services.chatService,
            taskService: services.taskService,
            currentUser: services.currentUser
        )
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
