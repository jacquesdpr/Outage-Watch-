import Foundation

@MainActor
final class MyTasksViewModel: ObservableObject {
    @Published private(set) var tasks: [StaffTask] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let taskService: TaskService
    private let currentUser: GraphUser?

    init(taskService: TaskService, currentUser: GraphUser?) {
        self.taskService = taskService
        self.currentUser = currentUser
    }

    var openCount: Int { tasks.filter { $0.status == .open }.count }

    func load() async {
        guard let currentUser else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            tasks = try await taskService.fetchAllMyTasks(userId: currentUser.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggle(_ task: StaffTask) async {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let newStatus: StaffTask.Status = task.status == .open ? .done : .open
        do {
            if newStatus == .done {
                try await taskService.markDone(itemId: task.itemId)
            } else {
                try await taskService.reopen(itemId: task.itemId)
            }
            tasks[index].status = newStatus
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
