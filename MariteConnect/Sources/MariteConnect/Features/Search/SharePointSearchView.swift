import SwiftUI

struct SharePointSearchView: View {
    @StateObject private var viewModel: SharePointSearchViewModel

    init(services: AppServices) {
        _viewModel = StateObject(wrappedValue: SharePointSearchViewModel(searchService: services.searchService))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("SharePoint Search")
                .searchable(text: $viewModel.query, prompt: "Search leases, reports, minutes…")
                .onSubmit(of: .search) { viewModel.search() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isSearching {
            LoadingView()
        } else if let error = viewModel.errorMessage {
            EmptyStateView(systemImage: "exclamationmark.triangle", title: "Search failed", message: error)
        } else if !viewModel.hasSearched {
            EmptyStateView(systemImage: "magnifyingglass", title: "Search all of SharePoint", message: "Find documents, reports, and lists across every site you have access to — results respect your existing permissions.")
        } else if viewModel.results.isEmpty {
            EmptyStateView(systemImage: "doc.text.magnifyingglass", title: "No results", message: "Try different keywords, or check the document is in a site you have access to.")
        } else {
            List(viewModel.results) { result in
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
    }
}

private extension String {
    /// Graph search summaries wrap matched terms in <c0>...</c0>; strip for a plain preview.
    var strippingHighlightTags: String {
        replacingOccurrences(of: "<c0>", with: "").replacingOccurrences(of: "</c0>", with: "")
            .replacingOccurrences(of: "<ddd/>", with: "…")
    }
}
