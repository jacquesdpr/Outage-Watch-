import Foundation

@MainActor
final class LegalLibraryViewModel: ObservableObject {
    @Published private(set) var documents: [LegalDocument] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isUploading = false
    @Published var errorMessage: String?

    private let legalLibrary: LegalLibraryService
    private let currentStaff: Staff

    init(legalLibrary: LegalLibraryService, currentStaff: Staff) {
        self.legalLibrary = legalLibrary
        self.currentStaff = currentStaff
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            documents = try await legalLibrary.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// `pickedURL` is the security-scoped URL SwiftUI's fileImporter hands
    /// back; it's copied to a plain temporary file first because CKAsset
    /// needs a stable, non-security-scoped path to read from when saving.
    func upload(title: String, pickedURL: URL) async {
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        let didAccess = pickedURL.startAccessingSecurityScopedResource()
        defer { if didAccess { pickedURL.stopAccessingSecurityScopedResource() } }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
        do {
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            try FileManager.default.copyItem(at: pickedURL, to: tempURL)
            try await legalLibrary.upload(title: title, localFileURL: tempURL, uploadedBy: currentStaff)
            try? FileManager.default.removeItem(at: tempURL)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
