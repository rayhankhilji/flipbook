import Foundation
import SwiftData

/// A distilled, compact representation of one book, produced once by `BookDistiller` and
/// reused forever after. A full book is often 250k–1M+ tokens — far too much (and far too
/// expensive) to send on every message. The digest compresses it to a few thousand tokens
/// that still carry the arguments, structure, voice, and verbatim quotes an author persona
/// needs to speak accurately about its own work.
@Model
public final class BookDigest {
    /// The `Book.id` this digest was built from — one digest per book.
    @Attribute(.unique) public var bookID: UUID

    public var bookTitle: String
    public var authorName: String

    /// The distilled text, structured by `BookDistiller` (overview, core arguments, section
    /// progression, key quotes, voice, worldview).
    public var digestText: String

    /// Characters of source text distilled, for cost/coverage reporting in the UI.
    public var sourceCharacterCount: Int
    /// How many map-phase chunks the book was split into.
    public var chunkCount: Int

    public var modelID: String
    public var providerRaw: String
    public var createdAt: Date

    /// Bumped when the distillation prompt/format changes so stale digests can be rebuilt.
    public static let currentFormatVersion = 1
    public var formatVersion: Int

    public init(
        bookID: UUID,
        bookTitle: String,
        authorName: String,
        digestText: String,
        sourceCharacterCount: Int,
        chunkCount: Int,
        modelID: String,
        providerRaw: String,
        createdAt: Date = .now,
        formatVersion: Int = BookDigest.currentFormatVersion
    ) {
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.authorName = authorName
        self.digestText = digestText
        self.sourceCharacterCount = sourceCharacterCount
        self.chunkCount = chunkCount
        self.modelID = modelID
        self.providerRaw = providerRaw
        self.createdAt = createdAt
        self.formatVersion = formatVersion
    }

    public var isStale: Bool { formatVersion < BookDigest.currentFormatVersion }
}
