import AppKit
import FlipbookCore
import Foundation
import Observation
import SwiftData

/// Per-window reading state for one open book. Owns the `BookDocument` and `PageRenderer`,
/// and persists position/zoom to the book's `ReadingProgress` row on a debounce — never on
/// every scroll tick.
@Observable
@MainActor
final class ReadingSession {
    let book: Book
    let document: BookDocument
    let renderer: PageRenderer

    private(set) var currentPageIndex: Int
    var zoom: CGFloat
    private(set) var navigationMode: NavigationMode

    /// One-shot programmatic navigation request (page-jump field, future TOC/bookmark taps).
    /// The active navigation view consumes it and resets it to nil.
    var scrollToRequest: ScrollToRequest?

    struct ScrollToRequest: Equatable {
        let pageIndex: Int
        private let token = UUID()
    }

    private let modelContext: ModelContext
    private let progress: ReadingProgress
    private var saveDebounceTask: Task<Void, Never>?

    var pageCount: Int { document.pageCount }

    var screenScale: CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2
    }

    init?(book: Book, modelContext: ModelContext) {
        let resolution = FileRelocationResolver.resolve(bookmarkData: book.fileBookmarkData)
        guard let url = resolution.url, let document = BookDocument(url: url) else {
            book.isMissing = true
            try? modelContext.save()
            return nil
        }
        if let refreshed = resolution.refreshedBookmarkData {
            book.fileBookmarkData = refreshed
        }

        self.book = book
        self.document = document
        self.renderer = PageRenderer(
            bookID: book.id,
            document: document,
            compositor: ThemeCompositor.shared.makeRendererHook()
        )
        self.modelContext = modelContext

        if let existing = book.progress {
            self.progress = existing
        } else {
            let appSettings = (try? modelContext.fetch(FetchDescriptor<AppSettings>()))?.first
            let created = ReadingProgress(
                book: book,
                zoomLevel: appSettings?.defaultZoom ?? 1.0,
                navigationMode: appSettings?.defaultNavigationMode ?? .pageTurn
            )
            modelContext.insert(created)
            book.progress = created
            self.progress = created
        }

        self.currentPageIndex = min(progress.currentPageIndex, max(document.pageCount - 1, 0))
        self.zoom = CGFloat(progress.zoomLevel)
        self.navigationMode = progress.navigationMode

        book.dateLastOpened = .now
        try? modelContext.save()
    }

    func setCurrentPage(_ index: Int) {
        let clamped = min(max(index, 0), max(pageCount - 1, 0))
        guard clamped != currentPageIndex else { return }
        currentPageIndex = clamped
        scheduleProgressSave()
    }

    func setZoom(_ newZoom: CGFloat) {
        zoom = min(max(newZoom, 0.5), 3.0)
        scheduleProgressSave()
    }

    func jump(toPage index: Int) {
        setCurrentPage(index)
        scrollToRequest = ScrollToRequest(pageIndex: currentPageIndex)
    }

    func setNavigationMode(_ mode: NavigationMode) {
        guard mode != navigationMode else { return }
        navigationMode = mode
        progress.navigationMode = mode
        try? modelContext.save()
    }

    // MARK: - Reflow

    /// Reflow presents the book's text re-typeset natively (user font/size/theme colors)
    /// instead of rasterized pages. Ephemeral per session.
    var reflowMode = false
    private(set) var reflowBlocks: [ReflowBlock]?
    private(set) var reflowAvailable: Bool?

    func checkReflowAvailability() async {
        guard reflowAvailable == nil else { return }
        reflowAvailable = await renderer.hasTextLayer()
    }

    func loadReflowContentIfNeeded() async {
        guard reflowBlocks == nil else { return }
        let texts = await renderer.extractPageTexts()
        reflowBlocks = ReflowExtractor.blocks(fromPageTexts: texts)
    }

    // MARK: - Bookmarks

    var isCurrentPageBookmarked: Bool {
        bookmark(forPage: currentPageIndex) != nil
    }

    func bookmark(forPage index: Int) -> Bookmark? {
        book.bookmarks.first(where: { $0.pageIndex == index })
    }

    func toggleBookmark() {
        if let existing = bookmark(forPage: currentPageIndex) {
            modelContext.delete(existing)
        } else {
            let created = Bookmark(book: book, pageIndex: currentPageIndex)
            modelContext.insert(created)
        }
        try? modelContext.save()
    }

    func removeBookmark(_ bookmark: Bookmark) {
        modelContext.delete(bookmark)
        try? modelContext.save()
    }

    // MARK: - Highlighter tool

    /// A marker you toggle on from the toolbar. While active, dragging on a page paints a
    /// free-form region highlight in the current color/style and tapping an existing mark
    /// erases it. Ephemeral — resets each time the book is opened.
    var highlighterActive = false
    var highlighterColorTag = "honey"
    var highlighterStyle = "highlight" // "highlight" | "underline"

    // MARK: - Highlights

    func highlights(forPage index: Int) -> [Highlight] {
        book.highlights.filter { $0.pageIndex == index }
    }

    func addHighlight(
        pageIndex: Int,
        kind: HighlightKind,
        rects: [CGRect],
        selectedText: String?,
        colorTag: String,
        styleTag: String = "highlight"
    ) {
        let highlight = Highlight(
            book: book,
            pageIndex: pageIndex,
            kind: kind,
            quadPointsData: QuadPoints.encode(rects),
            selectedText: selectedText,
            colorTag: colorTag,
            styleTag: styleTag
        )
        modelContext.insert(highlight)
        try? modelContext.save()
    }

    /// Persists a freehand pen mark: the stroke centerline (page space) plus its width,
    /// with the stroke's bounding box in `quadPointsData` for hit-testing and snippets.
    func addPenHighlight(
        pageIndex: Int,
        strokePoints: [CGPoint],
        strokeWidth: CGFloat,
        boundingBox: CGRect,
        selectedText: String?,
        colorTag: String,
        styleTag: String
    ) {
        let highlight = Highlight(
            book: book,
            pageIndex: pageIndex,
            kind: .region,
            quadPointsData: QuadPoints.encode([boundingBox]),
            strokePointsData: StrokePath.encode(strokePoints),
            strokeWidth: Double(strokeWidth),
            selectedText: selectedText,
            colorTag: colorTag,
            styleTag: styleTag
        )
        modelContext.insert(highlight)
        try? modelContext.save()
    }

    func removeHighlight(_ highlight: Highlight) {
        modelContext.delete(highlight)
        try? modelContext.save()
    }

    func updateNote(for highlight: Highlight, note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        highlight.note = trimmed.isEmpty ? nil : trimmed
        try? modelContext.save()
    }

    func image(forPage index: Int, themeID: String) async -> CGImage? {
        await renderer.image(pageIndex: index, zoom: zoom, themeID: themeID, screenScale: screenScale)
    }

    /// Warms the render cache around the current page. `renderZoom` must be the zoom the
    /// presenting view actually renders at (display points per page point) — a mismatched
    /// zoom or theme here renders bitmaps that are never shown, starving real requests.
    /// Only the view showing the pages knows that zoom, so it must be passed in.
    func prefetch(renderZoom: CGFloat, themeID: String) {
        let renderer = renderer
        let index = currentPageIndex
        let scale = screenScale
        Task(priority: .utility) {
            await renderer.prefetch(around: index, zoom: renderZoom, themeID: themeID, screenScale: scale)
        }
    }

    private func scheduleProgressSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            self.progress.currentPageIndex = self.currentPageIndex
            self.progress.zoomLevel = Double(self.zoom)
            self.progress.lastUpdated = .now
            try? self.modelContext.save()
        }
    }
}
