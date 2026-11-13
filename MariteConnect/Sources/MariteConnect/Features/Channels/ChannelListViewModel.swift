import Foundation

@MainActor
final class ChannelListViewModel: ObservableObject {
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let chatService: ChatService
    private let currentUserRecordName: String

    init(chatService: ChatService, currentUserRecordName: String) {
        self.chatService = chatService
        self.currentUserRecordName = currentUserRecordName
    }

    /// Only channels this person should see: every standard channel, plus
    /// any private channel they're a listed member of.
    var visibleChannels: [Channel] {
        channels.filter { $0.isVisible(to: currentUserRecordName) }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            channels = try await chatService.fetchChannels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
