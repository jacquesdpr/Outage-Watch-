import Foundation

@MainActor
final class MyTasksViewModel: ObservableObject {
    @Published private(set) var tasks: [StaffTask] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let taskService: TaskService
    private let currentStaff: Staff

    init(taskService: TaskService, currentStaff: Staff) {
        self.taskService = taskService
        self.currentStaff = currentStaff
    }

    var openCount: Int { tasks.filter { $0.status == .open }.count }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            tasks = try await taskService.fetchAllMyTasks(userRecordName: currentStaff.userRecordName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggle(_ task: StaffTask) async {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let newStatus: StaffTask.Status = task.status == .open ? .done : .open
        do {
            if newStatus == .done {
                try await taskService.markDone(recordName: task.recordName)
            } else {
                try await taskService.reopen(recordName: task.recordName)
            }
            tasks[index].status = newStatus
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
