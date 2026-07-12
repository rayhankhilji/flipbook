import CoreGraphics
import Foundation

/// Geometry for the book presentation: which pages form the current spread and where
/// each page sits. Shared by `PageTurnNSView` (layer layout) and `ReaderView` (the
/// SwiftUI annotations overlay), so the two never drift apart.
public struct BookSpreadLayout {
    public let leftPageIndex: Int?
    public let rightPageIndex: Int?
    public let leftRect: CGRect
    public let rightRect: CGRect
    public let bookRect: CGRect
    public let isSingle: Bool

    /// Spread numbering follows book convention: spread 0 is the cover alone,
    /// spread s ≥ 1 shows pages (2s-1, 2s).
    public static func spread(containing pageIndex: Int) -> Int {
        (pageIndex + 1) / 2
    }

    public static func pages(inSpread spread: Int, pageCount: Int) -> (left: Int?, right: Int?) {
        guard spread > 0 else {
            return (nil, pageCount > 0 ? 0 : nil)
        }
        let left = 2 * spread - 1
        let right = 2 * spread
        return (
            left < pageCount ? left : nil,
            right < pageCount ? right : nil
        )
    }

    public static func spreadCount(pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        return (pageCount + 1) / 2 + (pageCount.isMultiple(of: 2) ? 1 : 0)
    }

    /// The page index persisted as reading position for a spread — the furthest page.
    public static func committedIndex(forSpread spread: Int, pageCount: Int) -> Int {
        let pages = pages(inSpread: spread, pageCount: pageCount)
        return pages.right ?? pages.left ?? 0
    }

    /// Convenience for callers (and tests) whose pages share one size.
    public static func compute(
        bounds: CGSize,
        spread: Int,
        pageCount: Int,
        pageSize: CGSize
    ) -> BookSpreadLayout {
        compute(bounds: bounds, spread: spread, pageCount: pageCount) { _ in pageSize }
    }

    /// Each page's rect honors that page's own aspect ratio (mixed-size PDFs are common),
    /// so display code can stretch bitmaps edge-to-edge without distortion. The two pages
    /// share a display height and meet at the centered spine.
    public static func compute(
        bounds: CGSize,
        spread: Int,
        pageCount: Int,
        pageSize: (Int) -> CGSize
    ) -> BookSpreadLayout {
        let pages = pages(inSpread: spread, pageCount: pageCount)
        func safeSize(_ index: Int?) -> CGSize? {
            guard let index else { return nil }
            let size = pageSize(index)
            return CGSize(width: max(size.width, 1), height: max(size.height, 1))
        }
        let fallback = CGSize(width: 612, height: 792)

        // A narrow (portrait-ish) window can't hold a readable spread — fall back to
        // one page, keeping text as large as possible.
        let single = pages.left == nil || pages.right == nil || bounds.width < bounds.height * 1.05

        let horizontalMargin: CGFloat = 56
        let verticalMargin: CGFloat = 44
        let available = CGSize(
            width: max(bounds.width - horizontalMargin * 2, 50),
            height: max(bounds.height - verticalMargin * 2, 50)
        )

        if single {
            // Show whichever page exists; prefer the right (current) one.
            let onlyIndex = pages.right ?? pages.left
            let safePage = safeSize(onlyIndex) ?? fallback
            let scale = min(available.width / safePage.width, available.height / safePage.height)
            let size = CGSize(width: safePage.width * scale, height: safePage.height * scale)
            let rect = CGRect(
                x: bounds.width / 2 - size.width / 2,
                y: bounds.height / 2 - size.height / 2,
                width: size.width,
                height: size.height
            )
            return BookSpreadLayout(
                leftPageIndex: pages.right == nil ? pages.left : nil,
                rightPageIndex: pages.right,
                leftRect: rect,
                rightRect: rect,
                bookRect: rect.insetBy(dx: -14, dy: -12),
                isSingle: onlyIndex != nil ? single : true
            )
        }

        // A missing sibling (trailing odd spread) mirrors the other page so the book
        // silhouette stays stable across the turn.
        let leftSize = safeSize(pages.left) ?? safeSize(pages.right) ?? fallback
        let rightSize = safeSize(pages.right) ?? safeSize(pages.left) ?? fallback
        let leftAspect = leftSize.width / leftSize.height
        let rightAspect = rightSize.width / rightSize.height

        let height = min(available.height, available.width / (leftAspect + rightAspect))
        let spineX = bounds.width / 2
        let top = bounds.height / 2 - height / 2
        let leftRect = CGRect(
            x: spineX - height * leftAspect, y: top,
            width: height * leftAspect, height: height
        )
        let rightRect = CGRect(
            x: spineX, y: top,
            width: height * rightAspect, height: height
        )

        return BookSpreadLayout(
            leftPageIndex: pages.left,
            rightPageIndex: pages.right,
            leftRect: leftRect,
            rightRect: rightRect,
            bookRect: leftRect.union(rightRect).insetBy(dx: -14, dy: -12),
            isSingle: false
        )
    }
}
