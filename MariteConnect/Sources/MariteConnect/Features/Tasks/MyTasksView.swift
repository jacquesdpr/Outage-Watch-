import SwiftUI

struct MyTasksView: View {
    @StateObject private var viewModel: MyTasksViewModel

    init(services: AppServices) {
        _viewModel = StateObject(wrappedValue: MyTasksViewModel(taskService: services.taskService, currentUser: services.currentUser))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("My Tasks")
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.tasks.isEmpty {
            LoadingView()
        } else if viewModel.tasks.isEmpty {
            EmptyStateView(systemImage: "checkmark.circle", title: "All clear", message: "Tasks tagged to you across every channel will show up here until you confirm them done.")
        } else {
            List {
                if viewModel.openCount > 0 {
                    Section("Open (\(viewModel.openCount))") {
                        ForEach(viewModel.tasks.filter { $0.status == .open }) { task in
                            TaskRow(task: task) { Task { await viewModel.toggle(task) } }
                        }
                    }
                }
                Section("Completed") {
                    ForEach(viewModel.tasks.filter { $0.status == .done }) { task in
                        TaskRow(task: task) { Task { await viewModel.toggle(task) } }
                    }
                }
            }
            if let error = viewModel.errorMessage {
                ErrorBanner(message: error)
            }
        }
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
