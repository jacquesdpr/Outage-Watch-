import SwiftUI

struct MyTasksView: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var box = ViewModelBox()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("My Tasks")
                .task {
                    box.bind(services: services)
                    await box.model?.load()
                }
                .refreshable { await box.model?.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let model = box.model {
            if model.isLoading && model.tasks.isEmpty {
                LoadingView()
            } else if model.tasks.isEmpty {
                EmptyStateView(systemImage: "checkmark.circle", title: "All clear", message: "Tasks tagged to you across every channel will show up here until you confirm them done.")
            } else {
                List {
                    if model.openCount > 0 {
                        Section("Open (\(model.openCount))") {
                            ForEach(model.tasks.filter { $0.status == .open }) { task in
                                TaskRow(task: task) { Task { await model.toggle(task) } }
                            }
                        }
                    }
                    Section("Completed") {
                        ForEach(model.tasks.filter { $0.status == .done }) { task in
                            TaskRow(task: task) { Task { await model.toggle(task) } }
                        }
                    }
                }
                if let error = model.errorMessage {
                    ErrorBanner(message: error)
                }
            }
        } else {
            LoadingView()
        }
    }
}

@MainActor
private final class ViewModelBox: ObservableObject {
    @Published var model: MyTasksViewModel?

    func bind(services: AppServices) {
        guard model == nil else { return }
        model = MyTasksViewModel(taskService: services.taskService, currentUser: services.currentUser)
    }
}

private struct TaskRow: View {
    let task: StaffTask
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.status == .done ? .green : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.summary)
                        .font(.body)
                        .strikethrough(task.status == .done)
                        .foregroundStyle(.primary)
                    Text("#\(task.channelName) · from \(task.createdByName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
