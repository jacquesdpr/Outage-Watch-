import Foundation

/// Result row shown in the SharePoint search tab, built from a Microsoft Graph
/// Search API (`/search/query`) hit.
struct SharePointSearchResult: Identifiable, Hashable {
    let id: String
    let title: String
    let snippet: String
    let webUrl: String
    let lastModified: Date?
    let siteName: String?
}

// MARK: - /search/query wire format (trimmed to the fields we use)

struct GraphSearchRequestBody: Encodable {
    let requests: [SearchRequestEntry]
}

struct SearchRequestEntry: Encodable {
    let entityTypes: [String]
    let query: SearchQuery
    let from: Int
    let size: Int
}

struct SearchQuery: Encodable {
    let queryString: String
}

struct GraphSearchResponse: Decodable {
    let value: [SearchResponseValue]
}

struct SearchResponseValue: Decodable {
    let hitsContainers: [HitsContainer]
}

struct HitsContainer: Decodable {
    let hits: [SearchHit]
}

struct SearchHit: Decodable {
    let hitId: String
    let summary: String?
    let resource: SearchResource
}

struct SearchResource: Decodable {
    let name: String?
    let webUrl: String?
    let lastModifiedDateTime: Date?
    let parentReference: SearchParentReference?
}

struct SearchParentReference: Decodable {
    let siteId: String?
}

extension SharePointSearchResult {
    init(hit: SearchHit) {
        self.id = hit.hitId
        self.title = hit.resource.name ?? "Untitled"
        self.snippet = hit.summary ?? ""
        self.webUrl = hit.resource.webUrl ?? ""
        self.lastModified = hit.resource.lastModifiedDateTime
        self.siteName = hit.resource.parentReference?.siteId
    }
}
