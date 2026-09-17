import SwiftUI

struct SectionalTitleAssistantView: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var box = ViewModelBox()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let model = box.model {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(model.messages) { message in
                                    AssistantBubble(message: message).id(message.id)
                                }
                                if model.isThinking {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        Text("Checking the Act and CSOS records…").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding()
                        }
                        .onChange(of: model.messages.count) { _, _ in
                            if let last = model.messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }

                    if let error = model.errorMessage {
                        ErrorBanner(message: error)
                    }

                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("Ask a question or describe a scenario…", text: Binding(get: { model.draft }, set: { model.draft = $0 }), axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...6)
                        Button {
                            Task { await model.send() }
                        } label: {
                            Image(systemName: "paperplane.fill").font(.title2)
                        }
                        .disabled(!model.canSend)
                    }
                    .padding()
                    .background(.bar)
                } else {
                    LoadingView()
                }
            }
            .navigationTitle("Legal Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .task { box.bind(services: services) }
        }
    }
}

@MainActor
private final class ViewModelBox: ObservableObject {
    @Published var model: SectionalTitleAssistantViewModel?

    func bind(services: AppServices) {
        guard model == nil else { return }
        model = SectionalTitleAssistantViewModel(assistantService: services.assistantService)
    }
}

private struct AssistantBubble: View {
    let message: AssistantMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            Text(message.text)
                .padding(12)
                .background(message.role == .user ? Color.orange.opacity(0.15) : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            if !message.citations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(message.citations) { citation in
                        Link(destination: URL(string: citation.webUrl) ?? URL(string: "https://portal.office.com")!) {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "doc.text.fill").font(.caption)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(citation.documentTitle).font(.caption.bold())
                                    Text(citation.excerpt).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}
