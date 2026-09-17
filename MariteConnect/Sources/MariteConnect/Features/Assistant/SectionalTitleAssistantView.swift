import SwiftUI

struct SectionalTitleAssistantView: View {
    @StateObject private var viewModel: SectionalTitleAssistantViewModel

    init(services: AppServices) {
        _viewModel = StateObject(wrappedValue: SectionalTitleAssistantViewModel(assistantService: services.assistantService))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(viewModel.messages) { message in
                                AssistantBubble(message: message).id(message.id)
                            }
                            if viewModel.isThinking {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Checking the Act and CSOS records…").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let last = viewModel.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Ask a question or describe a scenario…", text: $viewModel.draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...6)
                    Button {
                        Task { await viewModel.send() }
                    } label: {
                        Image(systemName: "paperplane.fill").font(.title2)
                    }
                    .disabled(!viewModel.canSend)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Legal Assistant")
            .navigationBarTitleDisplayMode(.inline)
        }
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
