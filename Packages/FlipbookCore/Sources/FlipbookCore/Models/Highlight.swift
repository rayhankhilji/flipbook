import Foundation
import SwiftData

@Model
public final class Highlight {
    @Attribute(.unique) public var id: UUID
    public var book: Book?
    public var pageIndex: Int
    public var kind: HighlightKind

    /// Serialized `[CGRect]` quad points in PDF page space (both text-selection and
    /// region-based highlights render identically at display time from this data).
    public var quadPointsData: Data

    /// Populated for `.textSelection`, nil for `.region` (scanned pages with no text layer).
    public var selectedText: String?
    public var colorTag: String
    /// "highlight" (filled) or "underline" (bar under each line).
    public var styleTag: String = "highlight"
    public var note: String?
    public var dateCreated: Date

    public init(
        id: UUID = UUID(),
        book: Book? = nil,
        pageIndex: Int,
        kind: HighlightKind,
        quadPointsData: Data,
        selectedText: String? = nil,
        colorTag: String,
        styleTag: String = "highlight",
        note: String? = nil,
        dateCreated: Date = .now
    ) {
        self.id = id
        self.book = book
        self.pageIndex = pageIndex
        self.kind = kind
        self.quadPointsData = quadPointsData
        self.selectedText = selectedText
        self.colorTag = colorTag
        self.styleTag = styleTag
        self.note = note
        self.dateCreated = dateCreated
    }
}
