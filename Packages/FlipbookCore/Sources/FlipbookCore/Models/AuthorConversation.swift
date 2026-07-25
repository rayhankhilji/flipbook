import Foundation
import SwiftData

/// One saved conversation with an author persona. Several can exist per author — each with
/// its own scope (a single book, or everything that author has in the library) — so threads
/// stay separate the way they do in a real messaging app.
@Model
public final class AuthorConversation {
    @Attribute(.unique) public var id: UUID

    /// Matches `AuthorPersona.normalizedName`.
    public var authorNormalizedName: String
    public var authorDisplayName: String

    /// Title shown in the conversation list — auto-derived from the first message.
    public var title: String

    /// The book this thread is scoped to; nil means every book by this author.
    public var scopeBookID: UUID?
    public var scopeBookTitle: String?

    /// Transcript, encoded as JSON so no separate message entity/relationship is needed.
    public var transcriptData: Data

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        authorDisplayName: String,
        title: String = "New conversation",
        scopeBookID: UUID? = nil,
        scopeBookTitle: String? = nil,
        messages: [AIChatMessage] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.authorNormalizedName = AuthorPersona.normalize(authorDisplayName)
        self.authorDisplayName = authorDisplayName
        self.title = title
        self.scopeBookID = scopeBookID
        self.scopeBookTitle = scopeBookTitle
        self.transcriptData = (try? JSONEncoder().encode(messages)) ?? Data()
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var messages: [AIChatMessage] {
        get { (try? JSONDecoder().decode([AIChatMessage].self, from: transcriptData)) ?? [] }
        set {
            transcriptData = (try? JSONEncoder().encode(newValue)) ?? Data()
            updatedAt = .now
        }
    }

    /// Derives a short thread title from the first thing the reader asked.
    public func retitleFromFirstMessage() {
        guard title == "New conversation",
              let first = messages.first(where: { $0.role == .user })?.text
        else { return }
        let condensed = first.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        title = condensed.count > 48 ? String(condensed.prefix(48)) + "…" : condensed
    }
}
