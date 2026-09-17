import Foundation

@MainActor
final class ChannelListViewModel: ObservableObject {
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let chatService: ChatService

    init(chatService: ChatService) {
        self.chatService = chatService
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
