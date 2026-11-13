import CloudKit
import Foundation
import PDFKit

/// A legal-library document plus the plain text PDFKit extracted from it,
/// kept in memory for the life of the app so repeated questions don't
/// re-parse the same PDF every time.
struct ExtractedLegalDocument {
    let document: LegalDocument
    let text: String
}

/// The Sectional Title Legal Library: the STSMA Act, its regulations, and
/// curated CSOS adjudication orders, stored as CKAssets so every staff
/// member's copy stays in sync automatically. Extraction and search both
/// happen entirely on-device via PDFKit — no server, no SharePoint, no
/// separate search index.
final class LegalLibraryService {
    private let manager: CloudKitManager
    private var textCache: [String: String] = [:]

    init(manager: CloudKitManager) {
        self.manager = manager
    }

    func fetchAll() async throws -> [LegalDocument] {
        let query = CKQuery(recordType: RecordType.legalDocument, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        let (matchResults, _) = try await manager.publicDatabase.records(matching: query)
        return matchResults.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return LegalDocument(record: record)
        }
    }

    func upload(title: String, localFileURL: URL, uploadedBy: Staff) async throws {
        let record = LegalDocument.makeNewRecord(title: title, localFileURL: localFileURL, uploadedBy: uploadedBy)
        _ = try await manager.publicDatabase.save(record)
    }

    /// Returns up to `maxDocuments` documents whose extracted text best
    /// matches `query`'s first keyword, each with a short excerpt — the same
    /// shape the legal assistant needs to ground its answer.
    func findRelevant(query: String, maxDocuments: Int = 4) async throws -> [(document: LegalDocument, excerpt: String)] {
        let documents = try await fetchAll()
        let keyword = query.split(separator: " ").first.map(String.init)?.lowercased() ?? ""

        var scored: [(LegalDocument, String, Int)] = []
        for document in documents {
            guard let text = extractedText(for: document) else { continue }
            let lowercased = text.lowercased()
            let score = keyword.isEmpty ? 0 : lowercased.components(separatedBy: keyword).count - 1
            let excerpt = buildExcerpt(from: text, keyword: keyword)
            scored.append((document, excerpt, score))
        }

        return scored
            .sorted { $0.2 > $1.2 }
            .prefix(maxDocuments)
            .map { ($0.0, $0.1) }
    }

    private func extractedText(for document: LegalDocument) -> String? {
        if let cached = textCache[document.id] { return cached }
        guard let fileURL = document.fileURL, let pdf = PDFDocument(url: fileURL) else { return nil }
        var text = ""
        for pageIndex in 0..<pdf.pageCount {
            text += pdf.page(at: pageIndex)?.string ?? ""
            text += " "
        }
        textCache[document.id] = text
        return text
    }

    private func buildExcerpt(from text: String, keyword: String, windowSize: Int = 1200) -> String {
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !keyword.isEmpty, let range = normalized.range(of: keyword, options: .caseInsensitive) else {
            return String(normalized.prefix(windowSize))
        }
        let start = normalized.index(range.lowerBound, offsetBy: -min(windowSize / 4, normalized.distance(from: normalized.startIndex, to: range.lowerBound)))
        let end = normalized.index(start, offsetBy: windowSize, limitedBy: normalized.endIndex) ?? normalized.endIndex
        return String(normalized[start..<end])
    }
}
