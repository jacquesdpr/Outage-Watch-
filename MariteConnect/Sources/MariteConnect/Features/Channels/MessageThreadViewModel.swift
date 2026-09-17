import Foundation

@MainActor
final class MessageThreadViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var members: [GraphUser] = []
    @Published private(set) var myOpenTaskItemIds: Set<String> = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var draft: String = ""
    @Published var mentionTarget: GraphUser?

    let channel: Channel
    private let chatService: ChatService
    private let taskService: TaskService
    private let currentUser: GraphUser?

    init(channel: Channel, chatService: ChatService, taskService: TaskService, currentUser: GraphUser?) {
        self.channel = channel
        self.chatService = chatService
        self.taskService = taskService
        self.currentUser = currentUser
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let messagesTask = chatService.fetchMessages(channelId: channel.id)
            async let membersTask = chatService.fetchMembers(channelId: channel.id)
            messages = try await messagesTask
            members = try await membersTask
            if let currentUser {
                let myTasks = try await taskService.fetchMyOpenTasks(userId: currentUser.id)
                myOpenTaskItemIds = Set(myTasks.filter { $0.channelId == channel.id }.map(\.messageId))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func send() async {
        guard canSend, let currentUser else { return }
        let text = draft
        let assignee = mentionTarget
        draft = ""
        mentionTarget = nil

        do {
            if let assignee {
                try await chatService.sendTaskMessage(channelId: channel.id, channelName: channel.displayName, text: text, assignee: assignee, createdBy: currentUser)
            } else {
                try await chatService.sendMessage(channelId: channel.id, text: text)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
            draft = text
            mentionTarget = assignee
        }
    }

    /// Whether the current viewer needs to confirm this message's tagged task.
    func isConfirmable(message: ChatMessage) -> Bool {
        guard let currentUser else { return false }
        return message.mentions.contains { $0.mentioned.user?.id == currentUser.id } && myOpenTaskItemIds.contains(message.id)
    }

    func confirmDone(message: ChatMessage) async {
        guard let currentUser else { return }
        do {
            let tasks = try await taskService.fetchMyOpenTasks(userId: currentUser.id)
            guard let task = tasks.first(where: { $0.messageId == message.id }) else { return }
            try await taskService.markDone(itemId: task.itemId)
            myOpenTaskItemIds.remove(message.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
