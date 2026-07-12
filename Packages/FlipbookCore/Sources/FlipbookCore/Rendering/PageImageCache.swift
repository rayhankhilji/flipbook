import CoreGraphics
import Foundation

/// Cost-bounded cache of rendered page bitmaps. `NSCache` is thread-safe and evicts
/// by cost (bitmap byte size) under memory pressure, so no manual LRU bookkeeping.
public final class PageImageCache: @unchecked Sendable {
    private let cache = NSCache<PageCacheKey, CGImage>()

    public init(totalCostLimitBytes: Int = 250 * 1024 * 1024) {
        cache.totalCostLimit = totalCostLimitBytes
    }

    public func image(for key: PageCacheKey) -> CGImage? {
        cache.object(forKey: key)
    }

    public func insert(_ image: CGImage, for key: PageCacheKey) {
        let cost = image.bytesPerRow * image.height
        cache.setObject(image, forKey: key, cost: cost)
    }

    public func removeAll() {
        cache.removeAllObjects()
    }
}
