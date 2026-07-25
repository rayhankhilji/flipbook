import Foundation
import SwiftData

/// A movable note pinned to a spot on a page. Position is normalized to the page rect so it
/// tracks the page across window resizes and zoom; values may run slightly outside 0...1 so a
/// note can sit in the margin / dead space around the page. Collapsed by default (a small
/// tab); expanding it reveals the written text.
@Model
public final class StickyNote {
    @Attribute(.unique) public var id: UUID
    public var book: Book?
    public var pageIndex: Int
    /// Normalized position of the note's anchor within the page rect (0 = left/top).
    public var normalizedX: Double
    public var normalizedY: Double
    /// Plain-text mirror of the note body (tooltips, search, accessibility).
    public var text: String
    /// Rich-text body as RTF. Optional so notes written before rich editing keep working;
    /// when present it is the source of truth and `text` is its plain-text mirror.
    public var rtfData: Data?
    /// Palette key (see `StickyNotePalette`).
    public var colorTag: String
    public var isExpanded: Bool
    public var dateCreated: Date

    public init(
        id: UUID = UUID(),
        book: Book? = nil,
        pageIndex: Int,
        normalizedX: Double = 0.5,
        normalizedY: Double = 0.5,
        text: String = "",
        rtfData: Data? = nil,
        colorTag: String = "lemon",
        isExpanded: Bool = true,
        dateCreated: Date = .now
    ) {
        self.id = id
        self.book = book
        self.pageIndex = pageIndex
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.text = text
        self.rtfData = rtfData
        self.colorTag = colorTag
        self.isExpanded = isExpanded
        self.dateCreated = dateCreated
    }
}
