import SwiftUI

struct NewChannelView: View {
    let chatService: ChatService
    let staffDirectory: StaffDirectoryService
    let currentStaff: Staff
    let onCreated: (Channel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var isPrivate = false
    @State private var allStaff: [Staff] = []
    @State private var selectedMembers: Set<String> = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Channel") {
                    TextField("Name (e.g. maintenance-requests)", text: $name)
                    TextField("Description (optional)", text: $description)
                    Toggle("Private — certain people only", isOn: $isPrivate)
                }

                if isPrivate {
                    Section("Members") {
                        if allStaff.isEmpty {
                            Text("No one else has opened the app yet.").foregroundStyle(.secondary)
                        }
                        ForEach(allStaff) { staff in
                            Button {
                                toggle(staff)
                            } label: {
                                HStack {
                                    InitialsAvatar(name: staff.displayName)
                                    Text(staff.displayName).foregroundStyle(.primary)
                                    Spacer()
                                    if selectedMembers.contains(staff.userRecordName) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("New Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .task {
                allStaff = (try? await staffDirectory.fetchAll())?.filter { $0.userRecordName != currentStaff.userRecordName } ?? []
            }
        }
    }

    private func toggle(_ staff: Staff) {
        if selectedMembers.contains(staff.userRecordName) {
            selectedMembers.remove(staff.userRecordName)
        } else {
            selectedMembers.insert(staff.userRecordName)
        }
    }

    private func create() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let members = allStaff.filter { selectedMembers.contains($0.userRecordName) }
                let channel = try await chatService.createChannel(
                    name: name.trimmingCharacters(in: .whitespaces),
                    description: description.trimmingCharacters(in: .whitespaces),
                    isPrivate: isPrivate,
                    members: isPrivate ? members + [currentStaff] : [],
                    createdBy: currentStaff
                )
                onCreated(channel)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
