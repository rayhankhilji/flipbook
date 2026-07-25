import Foundation
import SwiftData

/// A user-created collection of books, shown in the library sidebar. A book may belong to
/// any number of folders (many-to-many). Deleting a folder never deletes its books.
@Model
public final class Folder {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var dateCreated: Date
    /// Manual ordering in the sidebar (lower first).
    public var sortIndex: Int
    /// SF Symbol shown beside the folder name.
    public var symbol: String

    @Relationship(inverse: \Book.folders)
    public var books: [Book] = []

    public init(
        id: UUID = UUID(),
        name: String,
        dateCreated: Date = .now,
        sortIndex: Int = 0,
        symbol: String = "folder"
    ) {
        self.id = id
        self.name = name
        self.dateCreated = dateCreated
        self.sortIndex = sortIndex
        self.symbol = symbol
    }
}
