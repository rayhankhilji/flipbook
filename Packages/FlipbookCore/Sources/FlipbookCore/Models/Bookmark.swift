import Foundation
import SwiftData

@Model
public final class Bookmark {
    @Attribute(.unique) public var id: UUID
    public var book: Book?
    public var pageIndex: Int
    public var label: String?
    public var dateCreated: Date
    public var colorTag: String?

    public init(
        id: UUID = UUID(),
        book: Book? = nil,
        pageIndex: Int,
        label: String? = nil,
        dateCreated: Date = .now,
        colorTag: String? = nil
    ) {
        self.id = id
        self.book = book
        self.pageIndex = pageIndex
        self.label = label
        self.dateCreated = dateCreated
        self.colorTag = colorTag
    }
}
