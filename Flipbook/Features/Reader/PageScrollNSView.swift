import AppKit
import FlipbookCore
import FlipbookDesignSystem
import SwiftUI

/// Native continuous-scroll engine. An `NSScrollView` owns all scrolling and trackpad
/// magnification — SwiftUI never mutates scroll position, which is what made the previous
/// implementation lurch and drift. Pages are virtualized tiles (bitmap layer + a SwiftUI
/// overlay hosting annotations and sticky notes) created only around the visible rect.
///
/// Pinch flow, Preview.app style: AppKit live-magnifies smoothly around the cursor; when the
/// gesture ends the effective zoom is committed — layout recomputed, magnification reset,
/// the exact document point under the viewport center restored, and tiles re-rendered crisp
/// at the new zoom bucket.
@MainActor
final class PageScrollNSView: NSScrollView {
    private weak var session: ReadingSession?

    private var themeID = ""
    private var theme: ThemeDefinition?
    private var zoom: CGFloat = 1

    private let doc = FlippedDocumentView()
    private var pageFrames: [CGRect] = []
    private var tiles: [Int: PageTileView] = [:]
    private var renderTasks: [Int: Task<Void, Never>] = [:]
    private var lastLayoutWidth: CGFloat = 0
    private var suppressPageTracking = false

    private let verticalPadding: CGFloat = 40
    private let pageGap: CGFloat = 24
    private let horizontalMargin: CGFloat = 40

    // MARK: Setup

    func configure(session: ReadingSession) {
        self.session = session

        documentView = doc
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        drawsBackground = true
        allowsMagnification = true
        minMagnification = 0.45
        maxMagnification = 4.0

        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipBoundsChanged),
            name: NSView.boundsDidChangeNotification, object: contentView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(liveMagnifyEnded),
            name: NSScrollView.didEndLiveMagnifyNotification, object: self
        )
    }

    // MARK: External updates (theme / zoom / settings)

    func apply(theme: ThemeDefinition, zoom: CGFloat, magnifyEnabled: Bool) {
        allowsMagnification = magnifyEnabled

        let themeChanged = theme.id != themeID
        let zoomChanged = zoom != self.zoom
        self.theme = theme
        self.themeID = theme.id
        self.zoom = zoom

        if themeChanged {
            backgroundColor = canvasNSColor(for: theme)
        }
        if zoomChanged || pageFrames.isEmpty {
            recomputeLayout(preservingCenter: true)
        }
        if themeChanged || zoomChanged {
            for (index, tile) in tiles {
                tile.updateChrome(theme: theme)
                render(pageIndex: index, into: tile)
                tile.refreshOverlay(session: session, theme: theme)
            }
        }
    }

    func scrollToPage(_ pageIndex: Int, animated: Bool = true) {
        guard pageFrames.indices.contains(pageIndex) else { return }
        let target = NSPoint(x: 0, y: max(pageFrames[pageIndex].minY - pageGap, 0))
        suppressPageTracking = true
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                contentView.animator().setBoundsOrigin(target)
            }, completionHandler: {
                Task { @MainActor [weak self] in
                    self?.suppressPageTracking = false
                    self?.clipBoundsChanged()
                }
            })
        } else {
            contentView.setBoundsOrigin(target)
            suppressPageTracking = false
        }
        reflectScrolledClipView(contentView)
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        if abs(bounds.width - lastLayoutWidth) > 0.5 {
            recomputeLayout(preservingCenter: lastLayoutWidth > 0)
        }
    }

    /// Computes every page frame at the current zoom and viewport, sizes the document,
    /// and (optionally) keeps the same document *fraction* under the viewport center.
    private func recomputeLayout(preservingCenter: Bool) {
        guard let session, bounds.width > 50 else { return }
        lastLayoutWidth = bounds.width

        let oldDocHeight = doc.frame.height
        let oldCenterFraction: CGFloat = oldDocHeight > 0
            ? (contentView.bounds.midY / oldDocHeight)
            : 0

        let fitWidth = min(max(bounds.width - horizontalMargin * 2, 200), 860)
        let pageWidth = fitWidth * zoom
        let docWidth = max(bounds.width, pageWidth + horizontalMargin * 2)

        var frames: [CGRect] = []
        frames.reserveCapacity(session.pageCount)
        var y = verticalPadding
        for index in 0..<session.pageCount {
            let size = session.document.pageSize(at: index)
            let height = size.width > 0 ? pageWidth * size.height / size.width : pageWidth * 1.4
            frames.append(CGRect(
                x: (docWidth - pageWidth) / 2, y: y, width: pageWidth, height: height
            ))
            y += height + pageGap
        }
        pageFrames = frames
        doc.frame = CGRect(x: 0, y: 0, width: docWidth, height: y - pageGap + verticalPadding)

        for (index, tile) in tiles where pageFrames.indices.contains(index) {
            tile.frame = pageFrames[index]
            tile.refreshOverlay(session: session, theme: theme)
        }

        if preservingCenter, oldDocHeight > 0 {
            let targetY = oldCenterFraction * doc.frame.height - contentView.bounds.height / 2
            contentView.setBoundsOrigin(NSPoint(
                x: contentView.bounds.origin.x,
                y: min(max(targetY, 0), max(doc.frame.height - contentView.bounds.height, 0))
            ))
            reflectScrolledClipView(contentView)
        }
        ensureTiles()
    }

    // MARK: Magnification commit

    @objc private func liveMagnifyEnded() {
        let m = magnification
        guard abs(m - 1) > 0.02, let session else {
            magnification = 1
            return
        }
        // The document point currently under the viewport center, as a fraction of the doc.
        let centerFraction = doc.frame.height > 0 ? contentView.bounds.midY / doc.frame.height : 0

        let newZoom = min(max(zoom * m, 0.5), 3.0)
        zoom = newZoom
        magnification = 1
        recomputeLayout(preservingCenter: false)

        let targetY = centerFraction * doc.frame.height - contentView.bounds.height / 2
        contentView.setBoundsOrigin(NSPoint(
            x: contentView.bounds.origin.x,
            y: min(max(targetY, 0), max(doc.frame.height - contentView.bounds.height, 0))
        ))
        reflectScrolledClipView(contentView)

        for (index, tile) in tiles {
            render(pageIndex: index, into: tile)
        }
        // Publish last: our own `apply` sees an unchanged zoom and does nothing.
        session.setZoom(newZoom)
    }

    // MARK: Virtualized tiles

    @objc private func clipBoundsChanged() {
        ensureTiles()
        guard !suppressPageTracking else { return }
        updateCurrentPage()
    }

    private func ensureTiles() {
        guard let session, let theme, !pageFrames.isEmpty else { return }
        let visible = contentView.bounds.insetBy(dx: 0, dy: -contentView.bounds.height)

        var wanted: Set<Int> = []
        for (index, frame) in pageFrames.enumerated() where frame.intersects(visible) {
            wanted.insert(index)
        }

        for (index, tile) in tiles where !wanted.contains(index) {
            renderTasks[index]?.cancel()
            renderTasks[index] = nil
            tile.removeFromSuperview()
            tiles[index] = nil
        }

        for index in wanted where tiles[index] == nil {
            let tile = PageTileView(pageIndex: index)
            tile.frame = pageFrames[index]
            tile.updateChrome(theme: theme)
            doc.addSubview(tile)
            tiles[index] = tile
            tile.refreshOverlay(session: session, theme: theme)
            render(pageIndex: index, into: tile)
        }
    }

    private func render(pageIndex: Int, into tile: PageTileView) {
        guard let session, pageFrames.indices.contains(pageIndex) else { return }
        let width = pageFrames[pageIndex].width
        let pageSize = session.document.pageSize(at: pageIndex)
        let renderZoom = pageSize.width > 0 ? width / pageSize.width : 1
        let themeID = self.themeID
        let scale = window?.backingScaleFactor ?? 2

        renderTasks[pageIndex]?.cancel()
        renderTasks[pageIndex] = Task { [weak self, weak tile] in
            let image = await session.renderer.image(
                pageIndex: pageIndex, zoom: renderZoom, themeID: themeID, screenScale: scale
            )
            guard !Task.isCancelled, let image, let tile, self != nil else { return }
            tile.setImage(image)
        }
    }

    // MARK: Page tracking

    private func updateCurrentPage() {
        guard let session, !pageFrames.isEmpty else { return }
        let centerY = contentView.bounds.midY
        // Binary search would work, but pageFrames is ordered and this runs on scroll
        // ticks over the visible window only after the first match.
        var best = session.currentPageIndex
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, frame) in pageFrames.enumerated() {
            let distance = abs(frame.midY - centerY)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            } else if frame.minY > centerY {
                break
            }
        }
        if best != session.currentPageIndex {
            session.setCurrentPage(best)
        }
    }

    private func canvasNSColor(for theme: ThemeDefinition) -> NSColor {
        let bg = theme.pageBackground
        if theme.isDark {
            return NSColor(
                srgbRed: min(bg.red + 0.045, 1), green: min(bg.green + 0.045, 1),
                blue: min(bg.blue + 0.045, 1), alpha: 1
            )
        }
        return NSColor(srgbRed: bg.red * 0.93, green: bg.green * 0.93, blue: bg.blue * 0.93, alpha: 1)
    }
}

/// AppKit documents are y-up; reading flows y-down.
final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// One page on the scroll surface: rendered bitmap as layer contents, paper shadow, and a
/// SwiftUI hosting view carrying the page's highlights, marker gesture, and sticky notes.
@MainActor
final class PageTileView: NSView {
    let pageIndex: Int
    private var hosting: NSHostingView<PageTileOverlay>?

    init(pageIndex: Int) {
        self.pageIndex = pageIndex
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 2
        layer?.shadowOffset = CGSize(width: 0, height: 4)
        layer?.shadowRadius = 10
        layer?.contentsGravity = .resize
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func updateChrome(theme: ThemeDefinition) {
        let bg = theme.pageBackground
        layer?.backgroundColor = CGColor(srgbRed: bg.red, green: bg.green, blue: bg.blue, alpha: 1)
        layer?.shadowOpacity = theme.isDark ? 0.5 : 0.22
        layer?.shadowColor = .black
    }

    func setImage(_ image: CGImage) {
        layer?.contents = image
    }

    /// (Re)mounts the SwiftUI overlay at the tile's current size.
    func refreshOverlay(session: ReadingSession?, theme: ThemeDefinition?) {
        guard let session, let theme else { return }
        let overlay = PageTileOverlay(
            session: session, pageIndex: pageIndex, size: frame.size, theme: theme
        )
        if let hosting {
            hosting.rootView = overlay
            hosting.frame = bounds
        } else {
            let view = NSHostingView(rootView: overlay)
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
            hosting = view
        }
    }
}

/// The SwiftUI layer riding on each page tile.
struct PageTileOverlay: View {
    let session: ReadingSession
    let pageIndex: Int
    let size: CGSize
    let theme: ThemeDefinition

    var body: some View {
        ZStack(alignment: .topLeading) {
            PageAnnotationsOverlay(
                session: session,
                pageIndex: pageIndex,
                displayedSize: size,
                theme: theme
            )
            StickyNotesPageLayer(session: session, pageIndex: pageIndex)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}
