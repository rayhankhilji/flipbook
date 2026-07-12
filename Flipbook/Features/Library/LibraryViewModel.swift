import FlipbookCore
import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class LibraryViewModel {
    var importErrorMessage: String?
    var isImporting = false

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func importPDFs(at urls: [URL]) {
        isImporting = true
        defer { isImporting = false }

        for url in urls where url.pathExtension.lowercased() == "pdf" {
            do {
                let book = try BookImporter.makeBook(from: url)
                modelContext.insert(book)
            } catch {
                importErrorMessage = "Couldn't import \(url.lastPathComponent)."
            }
        }
        try? modelContext.save()
    }

    func relink(_ book: Book, to url: URL) {
        do {
            book.fileBookmarkData = try SecurityScopedFileAccess.makeBookmarkData(for: url)
            book.lastKnownPath = url.path
            book.isMissing = false
            try? modelContext.save()
        } catch {
            importErrorMessage = "Couldn't relink \(book.title)."
        }
    }

    func remove(_ book: Book) {
        modelContext.delete(book)
        try? modelContext.save()
    }

    /// Re-checks file resolution for a book (e.g. after the user opens it), flagging it
    /// missing rather than silently failing so the Library can surface a relink affordance.
    func verifyFileResolution(for book: Book) {
        let resolution = FileRelocationResolver.resolve(bookmarkData: book.fileBookmarkData)
        book.isMissing = resolution.isMissing
        if let refreshed = resolution.refreshedBookmarkData {
            book.fileBookmarkData = refreshed
        }
        try? modelContext.save()
    }
}
