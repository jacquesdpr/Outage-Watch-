import Foundation

@MainActor
final class SharePointSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [SharePointSearchResult] = []
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?
    @Published private(set) var hasSearched = false

    private let searchService: SearchService
    private var searchTask: Task<Void, Never>?

    init(searchService: SearchService) {
        self.searchService = searchService
    }

    func search() {
        searchTask?.cancel()
        let text = query
        searchTask = Task {
            isSearching = true
            errorMessage = nil
            defer { isSearching = false }
            do {
                let found = try await searchService.search(query: text)
                if !Task.isCancelled {
                    results = found
                    hasSearched = true
                }
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }
}
