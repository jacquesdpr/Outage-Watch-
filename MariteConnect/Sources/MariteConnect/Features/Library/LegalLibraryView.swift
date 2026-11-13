import SwiftUI
import QuickLook
import UniformTypeIdentifiers

struct LegalLibraryView: View {
    @StateObject private var viewModel: LegalLibraryViewModel

    @State private var showingImporter = false
    @State private var pendingURL: URL?
    @State private var showingTitlePrompt = false
    @State private var pendingTitle = ""
    @State private var previewURL: URL?

    init(services: AppServices) {
        _viewModel = StateObject(wrappedValue: LegalLibraryViewModel(legalLibrary: services.legalLibrary, currentStaff: services.cloudKit.currentStaff!))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Legal Library")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingImporter = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(viewModel.isUploading)
                    }
                }
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
                .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf]) { result in
                    if case .success(let url) = result {
                        pendingURL = url
                        pendingTitle = url.deletingPathExtension().lastPathComponent
                        showingTitlePrompt = true
                    }
                }
                .alert("Name this document", isPresented: $showingTitlePrompt) {
                    TextField("Title", text: $pendingTitle)
                    Button("Cancel", role: .cancel) { pendingURL = nil }
                    Button("Add") {
                        if let url = pendingURL {
                            Task { await viewModel.upload(title: pendingTitle, pickedURL: url) }
                        }
                        pendingURL = nil
                    }
                } message: {
                    Text("This is shown as the citation title when the Legal Assistant references it.")
                }
                .quickLookPreview($previewURL)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.documents.isEmpty {
            LoadingView()
        } else if let error = viewModel.errorMessage, viewModel.documents.isEmpty {
            EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load the library", message: error)
        } else if viewModel.documents.isEmpty {
            EmptyStateView(systemImage: "doc.text.magnifyingglass", title: "No documents yet", message: "Tap + to add the STSMA Act, regulations, or a CSOS adjudication order (PDF).")
        } else {
            List(viewModel.documents) { document in
                Button {
                    previewURL = document.fileURL
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.title).foregroundStyle(.primary)
                        Text("Added by \(document.uploadedByName)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if viewModel.isUploading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Uploading…").foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }
        }
    }
}
