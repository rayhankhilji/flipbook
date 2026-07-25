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

    // MARK: - Book metadata

    func rename(_ book: Book, title: String, author: String) {
        book.title = title
        book.authorHint = author.isEmpty ? nil : author
        try? modelContext.save()
    }

    func toggleFavorite(_ book: Book) {
        book.isFavorite.toggle()
        try? modelContext.save()
    }

    func togglePin(_ book: Book) {
        book.isPinned.toggle()
        try? modelContext.save()
    }

    // MARK: - Folders

    @discardableResult
    func createFolder(name: String) -> Folder {
        let existing = (try? modelContext.fetch(FetchDescriptor<Folder>())) ?? []
        let nextIndex = (existing.map(\.sortIndex).max() ?? -1) + 1
        let folder = Folder(name: name, sortIndex: nextIndex)
        modelContext.insert(folder)
        try? modelContext.save()
        return folder
    }

    func renameFolder(_ folder: Folder, to name: String) {
        folder.name = name
        try? modelContext.save()
    }

    func deleteFolder(_ folder: Folder) {
        modelContext.delete(folder)
        try? modelContext.save()
    }

    func setMembership(_ book: Book, in folder: Folder, member: Bool) {
        if member {
            if !folder.books.contains(where: { $0.id == book.id }) {
                folder.books.append(book)
            }
        } else {
            folder.books.removeAll { $0.id == book.id }
        }
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
