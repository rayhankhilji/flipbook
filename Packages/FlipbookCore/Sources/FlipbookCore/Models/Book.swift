import Foundation
import SwiftData

/// A PDF imported into the library. The aggregate root for a book's reading state —
/// deleting a `Book` cascades to its `ReadingProgress`, `Bookmark`s, and `Highlight`s,
/// but never touches the file on disk (removal from disk is always a separate, explicit
/// user action).
@Model
public final class Book {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var authorHint: String?
    public var dateAdded: Date
    public var dateLastOpened: Date?
    public var pageCount: Int

    /// Security-scoped bookmark data, resolved on open to survive moves/renames/remounts.
    public var fileBookmarkData: Data
    /// Human-readable fallback path, shown in "Locate File…" relink UI if resolution fails.
    public var lastKnownPath: String
    public var fileSizeBytes: Int64

    @Attribute(.externalStorage) public var coverImageData: Data?

    /// True when the file couldn't be resolved on last attempt (moved/deleted/volume missing).
    /// Drives a "Locate File…" affordance rather than silently dropping the library entry.
    public var isMissing: Bool

    /// User-marked favourite (heart badge + Favourites shelf). Defaulted for lightweight migration.
    public var isFavorite: Bool = false
    /// Pinned books sort to the front of every shelf. Defaulted for lightweight migration.
    public var isPinned: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \ReadingProgress.book)
    public var progress: ReadingProgress?

    @Relationship(deleteRule: .cascade, inverse: \Bookmark.book)
    public var bookmarks: [Bookmark] = []

    @Relationship(deleteRule: .cascade, inverse: \Highlight.book)
    public var highlights: [Highlight] = []

    @Relationship(deleteRule: .cascade, inverse: \StickyNote.book)
    public var stickyNotes: [StickyNote] = []

    /// Folders this book belongs to (many-to-many). The inverse is declared on `Folder.books`.
    public var folders: [Folder] = []

    public init(
        id: UUID = UUID(),
        title: String,
        authorHint: String? = nil,
        dateAdded: Date = .now,
        dateLastOpened: Date? = nil,
        pageCount: Int,
        fileBookmarkData: Data,
        lastKnownPath: String,
        fileSizeBytes: Int64,
        coverImageData: Data? = nil,
        isMissing: Bool = false
    ) {
        self.id = id
        self.title = title
        self.authorHint = authorHint
        self.dateAdded = dateAdded
        self.dateLastOpened = dateLastOpened
        self.pageCount = pageCount
        self.fileBookmarkData = fileBookmarkData
        self.lastKnownPath = lastKnownPath
        self.fileSizeBytes = fileSizeBytes
        self.coverImageData = coverImageData
        self.isMissing = isMissing
    }
}
