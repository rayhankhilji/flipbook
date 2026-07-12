import Foundation

/// Handles the "file moved/renamed/deleted" case for a `Book` without ever dropping
/// the user's bookmarks/highlights just because the underlying file relocated.
public enum FileRelocationResolver {
    public struct Resolution {
        public let url: URL?
        public let refreshedBookmarkData: Data?
        public let isMissing: Bool
    }

    /// Attempts to resolve a book's file. On failure, returns `isMissing = true` so the
    /// caller can surface a "Locate File…" affordance rather than failing silently.
    public static func resolve(bookmarkData: Data) -> Resolution {
        do {
            let resolved = try SecurityScopedFileAccess.resolve(bookmarkData)
            return Resolution(
                url: resolved.url,
                refreshedBookmarkData: resolved.wasStale ? resolved.bookmarkData : nil,
                isMissing: false
            )
        } catch {
            return Resolution(url: nil, refreshedBookmarkData: nil, isMissing: true)
        }
    }

    /// Heuristic re-link: looks for a same-named file with a matching page count in the
    /// last known directory — the common "user moved the containing folder" case.
    public static func suggestedRelink(lastKnownPath: String, expectedPageCount: Int) -> URL? {
        let lastKnownURL = URL(fileURLWithPath: lastKnownPath)
        let directory = lastKnownURL.deletingLastPathComponent()
        let filename = lastKnownURL.lastPathComponent

        let candidate = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        guard let document = BookDocument(url: candidate) else { return nil }
        guard document.pageCount == expectedPageCount else { return nil }
        return candidate
    }
}
