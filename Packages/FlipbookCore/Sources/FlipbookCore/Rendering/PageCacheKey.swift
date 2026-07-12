import Foundation

/// Cache key for a rendered page image. Zoom is quantized into discrete buckets
/// (steps of 0.25×) so minor pinch jitter doesn't explode cache cardinality.
public final class PageCacheKey: NSObject, Sendable {
    public let bookID: UUID
    public let pageIndex: Int
    public let zoomBucket: Int
    public let themeID: String

    public init(bookID: UUID, pageIndex: Int, zoomBucket: Int, themeID: String) {
        self.bookID = bookID
        self.pageIndex = pageIndex
        self.zoomBucket = zoomBucket
        self.themeID = themeID
    }

    public convenience init(bookID: UUID, pageIndex: Int, zoom: CGFloat, themeID: String) {
        self.init(
            bookID: bookID,
            pageIndex: pageIndex,
            zoomBucket: PageCacheKey.bucket(forZoom: zoom),
            themeID: themeID
        )
    }

    /// Quantizes a zoom level to the nearest bucket at or above it, so cached images
    /// are only ever displayed at or below their rendered resolution (never upscaled).
    public static func bucket(forZoom zoom: CGFloat) -> Int {
        Int((zoom * 4).rounded(.up))
    }

    public static func zoom(forBucket bucket: Int) -> CGFloat {
        CGFloat(bucket) / 4
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PageCacheKey else { return false }
        return bookID == other.bookID
            && pageIndex == other.pageIndex
            && zoomBucket == other.zoomBucket
            && themeID == other.themeID
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(bookID)
        hasher.combine(pageIndex)
        hasher.combine(zoomBucket)
        hasher.combine(themeID)
        return hasher.finalize()
    }
}
