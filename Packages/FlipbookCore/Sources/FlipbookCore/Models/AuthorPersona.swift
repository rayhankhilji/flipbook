import Foundation
import SwiftData

/// A persistent personality file for one author, built once from the digests of their books
/// in the library plus the model's own knowledge of them. Injected as the system prompt when
/// the reader talks to that author, so the persona is stable across sessions and
/// conversations rather than re-improvised each time.
@Model
public final class AuthorPersona {
    /// Author name, normalized for matching (case/whitespace-insensitive key).
    @Attribute(.unique) public var normalizedName: String
    /// Display name as it appears on the books.
    public var displayName: String

    /// The persona injection: voice, biography, documented beliefs, recurring themes, and
    /// how this author characteristically advises.
    public var profileText: String

    /// Which books fed the profile, so the UI can show coverage and detect new additions.
    public var sourceBookIDs: [UUID]

    public var modelID: String
    public var providerRaw: String
    public var createdAt: Date
    public var updatedAt: Date

    public static let currentFormatVersion = 1
    public var formatVersion: Int

    public init(
        displayName: String,
        profileText: String,
        sourceBookIDs: [UUID],
        modelID: String,
        providerRaw: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        formatVersion: Int = AuthorPersona.currentFormatVersion
    ) {
        self.normalizedName = AuthorPersona.normalize(displayName)
        self.displayName = displayName
        self.profileText = profileText
        self.sourceBookIDs = sourceBookIDs
        self.modelID = modelID
        self.providerRaw = providerRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.formatVersion = formatVersion
    }

    public static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public var isStale: Bool { formatVersion < AuthorPersona.currentFormatVersion }
}
