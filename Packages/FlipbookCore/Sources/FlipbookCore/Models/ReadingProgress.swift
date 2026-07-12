import Foundation
import SwiftData

/// Per-book reading position, 1:1 with `Book`. Writes are debounced by the owning
/// `ReadingSession` (not on every scroll tick) before being saved here.
@Model
public final class ReadingProgress {
    public var book: Book?
    public var currentPageIndex: Int
    /// Sub-page scroll position within `currentPageIndex`, for continuous-scroll mode.
    public var scrollOffsetFraction: Double
    public var zoomLevel: Double
    public var navigationMode: NavigationMode
    public var lastUpdated: Date
    public var totalReadingSeconds: TimeInterval

    public init(
        book: Book? = nil,
        currentPageIndex: Int = 0,
        scrollOffsetFraction: Double = 0,
        zoomLevel: Double = 1.0,
        navigationMode: NavigationMode = .pageTurn,
        lastUpdated: Date = .now,
        totalReadingSeconds: TimeInterval = 0
    ) {
        self.book = book
        self.currentPageIndex = currentPageIndex
        self.scrollOffsetFraction = scrollOffsetFraction
        self.zoomLevel = zoomLevel
        self.navigationMode = navigationMode
        self.lastUpdated = lastUpdated
        self.totalReadingSeconds = totalReadingSeconds
    }
}
