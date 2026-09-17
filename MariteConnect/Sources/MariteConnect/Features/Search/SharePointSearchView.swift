import SwiftUI

struct SharePointSearchView: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var box = ViewModelBox()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("SharePoint Search")
                .searchable(text: Binding(get: { box.model?.query ?? "" }, set: { box.model?.query = $0 }), prompt: "Search leases, reports, minutes…")
                .onSubmit(of: .search) { box.model?.search() }
                .task { box.bind(services: services) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let model = box.model {
            if model.isSearching {
                LoadingView()
            } else if let error = model.errorMessage {
                EmptyStateView(systemImage: "exclamationmark.triangle", title: "Search failed", message: error)
            } else if !model.hasSearched {
                EmptyStateView(systemImage: "magnifyingglass", title: "Search all of SharePoint", message: "Find documents, reports, and lists across every site you have access to — results respect your existing permissions.")
            } else if model.results.isEmpty {
                EmptyStateView(systemImage: "doc.text.magnifyingglass", title: "No results", message: "Try different keywords, or check the document is in a site you have access to.")
            } else {
                List(model.results) { result in
                    Link(destination: URL(string: result.webUrl) ?? URL(string: "https://portal.office.com")!) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title).font(.body).foregroundStyle(.primary)
                            if !result.snippet.isEmpty {
                                Text(result.snippet.strippingHighlightTags)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        } else {
            LoadingView()
        }
    }
}

@MainActor
private final class ViewModelBox: ObservableObject {
    @Published var model: SharePointSearchViewModel?

    func bind(services: AppServices) {
        guard model == nil else { return }
        model = SharePointSearchViewModel(searchService: services.searchService)
    }
}

private extension String {
    /// Graph search summaries wrap matched terms in <c0>...</c0>; strip for a plain preview.
    var strippingHighlightTags: String {
        replacingOccurrences(of: "<c0>", with: "").replacingOccurrences(of: "</c0>", with: "")
            .replacingOccurrences(of: "<ddd/>", with: "…")
    }
}
