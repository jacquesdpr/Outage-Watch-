import Foundation

/// Wires up the Graph client and every feature service from a single shared
/// AuthManager, and caches the signed-in user's own Graph identity (needed to
/// stamp "createdBy" on tasks and to filter "my tasks").
@MainActor
final class AppServices: ObservableObject {
    let graph: GraphClient
    let chatService: ChatService
    let taskService: TaskService
    let searchService: SearchService
    let assistantService: AssistantService
    let pushNotificationService: PushNotificationService

    @Published private(set) var currentUser: GraphUser?

    init(authManager: AuthManager) {
        let graph = GraphClient(authManager: authManager)
        let taskService = TaskService(graph: graph)
        let pushNotificationService = PushNotificationService(authManager: authManager)
        self.graph = graph
        self.taskService = taskService
        self.pushNotificationService = pushNotificationService
        self.chatService = ChatService(graph: graph, taskService: taskService, pushNotificationService: pushNotificationService)
        self.searchService = SearchService(graph: graph)
        self.assistantService = AssistantService(authManager: authManager)
    }

    func loadCurrentUser() async {
        guard currentUser == nil else { return }
        currentUser = try? await graph.get("me", queryItems: [URLQueryItem(name: "$select", value: "id,displayName,userType")])
    }
}
