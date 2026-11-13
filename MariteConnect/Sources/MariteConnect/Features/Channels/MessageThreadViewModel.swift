import Foundation

@MainActor
final class MessageThreadViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var draft: String = ""
    @Published var mentionTarget: Staff?
    @Published private(set) var myOpenTaskMessageRecordNames: Set<String> = []

    let channel: Channel
    private let chatService: ChatService
    private let taskService: TaskService
    private let currentStaff: Staff

    init(channel: Channel, chatService: ChatService, taskService: TaskService, currentStaff: Staff) {
        self.channel = channel
        self.chatService = chatService
        self.taskService = taskService
        self.currentStaff = currentStaff
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let messagesTask = chatService.fetchMessages(channelRecordName: channel.recordName)
            async let tasksTask = taskService.fetchOpenTasks(assignedToUserRecordName: currentStaff.userRecordName)
            messages = try await messagesTask
            let myTasks = try await tasksTask
            myOpenTaskMessageRecordNames = Set(myTasks.filter { $0.channelRecordName == channel.recordName }.map(\.messageRecordName))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func send() async {
        guard canSend else { return }
        let text = draft
        let assignee = mentionTarget
        draft = ""
        mentionTarget = nil

        do {
            if let assignee {
                try await chatService.sendTaskMessage(channelRecordName: channel.recordName, channelName: channel.name, text: text, assignee: assignee, sender: currentStaff)
            } else {
                try await chatService.sendMessage(channelRecordName: channel.recordName, text: text, sender: currentStaff)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
            draft = text
            mentionTarget = assignee
        }
    }

    func isConfirmable(message: ChatMessage) -> Bool {
        message.taggedUserRecordName == currentStaff.userRecordName && myOpenTaskMessageRecordNames.contains(message.recordName)
    }

    func confirmDone(message: ChatMessage) async {
        do {
            let myTasks = try await taskService.fetchOpenTasks(assignedToUserRecordName: currentStaff.userRecordName)
            guard let task = myTasks.first(where: { $0.messageRecordName == message.recordName }) else { return }
            try await taskService.markDone(recordName: task.recordName)
            myOpenTaskMessageRecordNames.remove(message.recordName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
