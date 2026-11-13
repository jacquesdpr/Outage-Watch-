import Foundation

/// Wires up every service from the single shared CloudKitManager.
@MainActor
final class AppServices: ObservableObject {
    let cloudKit: CloudKitManager
    let staffDirectory: StaffDirectoryService
    let chatService: ChatService
    let taskService: TaskService
    let legalLibrary: LegalLibraryService
    let assistantService: AssistantService

    init(cloudKit: CloudKitManager) {
        self.cloudKit = cloudKit
        self.staffDirectory = StaffDirectoryService(manager: cloudKit)
        let taskService = TaskService(manager: cloudKit)
        self.taskService = taskService
        self.chatService = ChatService(manager: cloudKit, taskService: taskService)
        let legalLibrary = LegalLibraryService(manager: cloudKit)
        self.legalLibrary = legalLibrary
        self.assistantService = AssistantService(legalLibrary: legalLibrary)
    }
}
