import Foundation
import SwiftData

/// Builds a `Book` model instance from a PDF on disk — opens it just long enough to
/// extract metadata and a cover thumbnail, then hands back a row ready to insert.
public enum BookImporter {
    public enum ImportError: Error {
        case unreadablePDF
        case bookmarkCreationFailed
    }

    public static func makeBook(from url: URL) throws -> Book {
        guard let document = BookDocument(url: url) else {
            throw ImportError.unreadablePDF
        }

        let bookmarkData: Data
        do {
            bookmarkData = try SecurityScopedFileAccess.makeBookmarkData(for: url)
        } catch {
            throw ImportError.bookmarkCreationFailed
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? Int64) ?? 0

        var coverData: Data?
        if let cgImage = document.renderCoverThumbnail() {
            coverData = cgImage.pngData()
        }

        return Book(
            title: document.title,
            authorHint: document.authorHint,
            pageCount: document.pageCount,
            fileBookmarkData: bookmarkData,
            lastKnownPath: url.path,
            fileSizeBytes: fileSize,
            coverImageData: coverData
        )
    }
}
