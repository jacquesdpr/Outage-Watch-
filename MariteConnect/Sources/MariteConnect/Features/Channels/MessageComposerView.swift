import SwiftUI

struct MessageComposerView: View {
    @ObservedObject var model: MessageThreadViewModel
    let channel: Channel
    let staffDirectory: StaffDirectoryService

    @State private var showingMentionPicker = false
    @State private var candidates: [Staff] = []

    var body: some View {
        VStack(spacing: 6) {
            if let mentionTarget = model.mentionTarget {
                HStack {
                    Image(systemName: "at").foregroundStyle(.orange)
                    Text("Tagging \(mentionTarget.displayName) — they must confirm this is done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.mentionTarget = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    showingMentionPicker = true
                } label: {
                    Image(systemName: "at.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
                .accessibilityLabel("Tag someone")

                TextField("Message #\(channel.name)", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)

                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                }
                .disabled(!model.canSend)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 6)
        .background(.bar)
        .task {
            let all = (try? await staffDirectory.fetchAll()) ?? []
            candidates = channel.isPrivate ? all.filter { channel.memberUserRecordNames.contains($0.userRecordName) } : all
        }
        .sheet(isPresented: $showingMentionPicker) {
            MentionPickerView(members: candidates) { staff in
                model.mentionTarget = staff
                showingMentionPicker = false
            }
        }
    }
}
