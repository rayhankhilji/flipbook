import Foundation
import SwiftData

@Model
public final class Highlight {
    @Attribute(.unique) public var id: UUID
    public var book: Book?
    public var pageIndex: Int
    public var kind: HighlightKind

    /// Serialized `[CGRect]` quad points in PDF page space. Used by legacy text/region
    /// highlights; freehand pen marks store their geometry in `strokePointsData` instead
    /// and leave this holding the stroke's bounding box (for hit-testing and snippets).
    public var quadPointsData: Data

    /// Freehand "pen" geometry: the stroke centerline as `[CGPoint]` in PDF page space
    /// (see `StrokePath`). Nil for legacy rect-based highlights.
    public var strokePointsData: Data?
    /// Pen stroke width in PDF page points. 0 for legacy rect-based highlights.
    public var strokeWidth: Double = 0

    /// Populated for `.textSelection`, nil for `.region` (scanned pages with no text layer).
    public var selectedText: String?
    public var colorTag: String
    /// "highlight" (thick translucent marker) or "underline" (thin solid pen).
    public var styleTag: String = "highlight"
    public var note: String?
    public var dateCreated: Date

    public init(
        id: UUID = UUID(),
        book: Book? = nil,
        pageIndex: Int,
        kind: HighlightKind,
        quadPointsData: Data,
        strokePointsData: Data? = nil,
        strokeWidth: Double = 0,
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
        self.strokePointsData = strokePointsData
        self.strokeWidth = strokeWidth
        self.selectedText = selectedText
        self.colorTag = colorTag
        self.styleTag = styleTag
        self.note = note
        self.dateCreated = dateCreated
    }
}
