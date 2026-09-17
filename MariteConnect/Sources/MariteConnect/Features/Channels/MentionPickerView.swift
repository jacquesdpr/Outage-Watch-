import SwiftUI

struct MentionPickerView: View {
    let members: [GraphUser]
    let onSelect: (GraphUser) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [GraphUser] {
        guard !query.isEmpty else { return members }
        return members.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.id) { user in
                Button {
                    onSelect(user)
                } label: {
                    HStack {
                        InitialsAvatar(name: user.displayName)
                        Text(user.displayName).foregroundStyle(.primary)
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
