import SwiftUI

struct MentionPickerView: View {
    let members: [Staff]
    let onSelect: (Staff) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [Staff] {
        guard !query.isEmpty else { return members }
        return members.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { staff in
                Button {
                    onSelect(staff)
                } label: {
                    HStack {
                        InitialsAvatar(name: staff.displayName)
                        Text(staff.displayName).foregroundStyle(.primary)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search staff")
            .navigationTitle("Tag someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
