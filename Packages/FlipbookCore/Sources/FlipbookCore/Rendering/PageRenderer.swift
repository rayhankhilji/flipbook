import CoreGraphics
import Foundation
import PDFKit

/// Actor-isolated page rasterization service. All `PDFPage` drawing happens inside this
/// actor (off the main thread by construction, serialized so PDFKit is never re-entered),
/// and the main thread only ever receives finished `CGImage`s.
public actor PageRenderer {
    private let bookID: UUID
    private let document: BookDocument
    private let cache: PageImageCache

    /// Theme filtering hook — identity for now; `ThemeCompositor` (M3) plugs in here so
    /// filtered pixels are cached once per (page, zoom, theme), not recomputed per frame.
    private let compositor: (@Sendable (CGImage, String) -> CGImage)?

    private var prefetchTask: Task<Void, Never>?

    public init(
        bookID: UUID,
        document: BookDocument,
        cache: PageImageCache = PageImageCache(),
        compositor: (@Sendable (CGImage, String) -> CGImage)? = nil
    ) {
        self.bookID = bookID
        self.document = document
        self.cache = cache
        self.compositor = compositor
    }

    /// Returns a rendered page image, from cache when possible. `zoom` is quantized to
    /// buckets; the returned image is rendered at bucket resolution ≥ the requested zoom
    /// so display code can downscale (cheap) but never upscales (blurry).
    public func image(
        pageIndex: Int,
        zoom: CGFloat,
        themeID: String,
        screenScale: CGFloat
    ) -> CGImage? {
        let key = PageCacheKey(bookID: bookID, pageIndex: pageIndex, zoom: zoom, themeID: themeID)
        if let cached = cache.image(for: key) {
            return cached
        }
        // A cancelled caller must not pay for (or make everyone else queue behind) a render
        // it will never use — stale prefetches piling up here is what starves the request
        // for the page actually on screen.
        guard !Task.isCancelled else { return nil }

        let bucketZoom = PageCacheKey.zoom(forBucket: key.zoomBucket)
        guard var rendered = renderPage(at: pageIndex, zoom: bucketZoom, screenScale: screenScale) else {
            return nil
        }
        if let compositor {
            rendered = compositor(rendered, themeID)
        }
        cache.insert(rendered, for: key)
        return rendered
    }

    /// Warms the cache around the current page. Cancels any prior prefetch so fast
    /// navigation (e.g. a TOC jump) doesn't waste work rendering stale pages.
    public func prefetch(
        around pageIndex: Int,
        zoom: CGFloat,
        themeID: String,
        screenScale: CGFloat
    ) {
        prefetchTask?.cancel()
        let window = (pageIndex - 2)...(pageIndex + 3)
        let indices = window.filter { $0 >= 0 && $0 < document.pageCount && $0 != pageIndex }
        prefetchTask = Task(priority: .utility) {
            for index in indices {
                if Task.isCancelled { return }
                _ = self.image(pageIndex: index, zoom: zoom, themeID: themeID, screenScale: screenScale)
                await Task.yield()
            }
        }
    }

    // MARK: - Text extraction (actor-serialized like all other PDFKit access)

    /// Raw text of every page, for reflow mode.
    public func extractPageTexts() -> [String] {
        (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
    }

    /// Whether the document has any usable text layer (sampled from the first pages).
    public func hasTextLayer(sampleSize: Int = 8) -> Bool {
        for index in 0..<min(sampleSize, document.pageCount) {
            let text = document.page(at: index)?.string?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.count > 40 { return true }
        }
        return false
    }

    // MARK: - Rasterization

    private func renderPage(at pageIndex: Int, zoom: CGFloat, screenScale: CGFloat) -> CGImage? {
        guard let page = document.page(at: pageIndex) else { return nil }

        let displaySize = document.pageSize(at: pageIndex)
        let scale = max(zoom, 0.25) * max(screenScale, 1)
        let pixelWidth = Int((displaySize.width * scale).rounded())
        let pixelHeight = Int((displaySize.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        // PDFs assume a white page behind translucent/unpainted regions.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.interpolationQuality = .high
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()

        return context.makeImage()
    }
}
