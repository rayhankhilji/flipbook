import Foundation

/// Wraps bookmark-data creation/resolution for tracking a PDF's on-disk location.
///
/// Flipbook is directly distributed (Developer ID, no App Sandbox), so a plain security
/// scope isn't mandatory — but bookmark data still tracks file identity through renames
/// and moves on the same volume far more robustly than a raw path string, at no extra cost.
public enum SecurityScopedFileAccess {
    public struct ResolvedFile {
        public let url: URL
        public let bookmarkData: Data
        public let wasStale: Bool
    }

    public enum ResolutionError: Error {
        case bookmarkResolutionFailed
        case fileNoLongerExists
    }

    public static func makeBookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves bookmark data back to a URL, re-encoding fresh bookmark data if it was stale.
    public static func resolve(_ bookmarkData: Data) throws -> ResolvedFile {
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw ResolutionError.bookmarkResolutionFailed
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ResolutionError.fileNoLongerExists
        }

        let freshData = isStale ? (try? makeBookmarkData(for: url)) ?? bookmarkData : bookmarkData
        return ResolvedFile(url: url, bookmarkData: freshData, wasStale: isStale)
    }
}
