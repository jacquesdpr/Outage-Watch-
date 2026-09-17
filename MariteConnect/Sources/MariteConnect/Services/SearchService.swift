import Foundation

/// Searches SharePoint (documents, list items, and sites) through the Microsoft
/// Graph Search API, scoped to whatever the signed-in user already has permission
/// to see — no separate index or permissions model to maintain.
final class SearchService {
    private let graph: GraphClient

    init(graph: GraphClient) {
        self.graph = graph
    }

    func search(query: String) async throws -> [SharePointSearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let body = GraphSearchRequestBody(requests: [
            SearchRequestEntry(entityTypes: ["driveItem", "listItem"], query: SearchQuery(queryString: query), from: 0, size: 25)
        ])
        let response: GraphSearchResponse = try await graph.post("search/query", body: body)
        let hits = response.value.flatMap { $0.hitsContainers.flatMap(\.hits) }
        return hits.map(SharePointSearchResult.init)
    }
}
