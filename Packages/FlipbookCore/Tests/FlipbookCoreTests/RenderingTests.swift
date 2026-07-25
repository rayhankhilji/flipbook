import CoreGraphics
import Foundation
import PDFKit
import Testing

@testable import FlipbookCore

@Suite struct PageCacheKeyTests {
    @Test func bucketsQuantizeUpward() {
        #expect(PageCacheKey.bucket(forZoom: 1.0) == 4)
        #expect(PageCacheKey.bucket(forZoom: 0.3) == 2)
        #expect(PageCacheKey.bucket(forZoom: 1.1) == 5)
        #expect(PageCacheKey.zoom(forBucket: 4) == 1.0)
    }

    @Test func bucketZoomNeverBelowRequested() {
        for zoom in stride(from: 0.5, through: 3.0, by: 0.05) {
            let bucket = PageCacheKey.bucket(forZoom: zoom)
            #expect(PageCacheKey.zoom(forBucket: bucket) >= CGFloat(zoom) - 0.0001)
        }
    }

    @Test func keysEqualByValue() {
        let id = UUID()
        let a = PageCacheKey(bookID: id, pageIndex: 3, zoomBucket: 4, themeID: "sepia")
        let b = PageCacheKey(bookID: id, pageIndex: 3, zoomBucket: 4, themeID: "sepia")
        let c = PageCacheKey(bookID: id, pageIndex: 3, zoomBucket: 4, themeID: "midnight")
        #expect(a == b)
        #expect(a.hash == b.hash)
        #expect(a != c)
    }
}

@Suite struct PageRendererTests {
    private func makeFixturePDF(pageCount: Int = 3) throws -> URL {
        let document = PDFDocument()
        for index in 0..<pageCount {
            document.insert(PDFPage(), at: index)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flipbook-fixture-\(UUID().uuidString).pdf")
        guard document.write(to: url) else {
            throw NSError(domain: "fixture", code: 1)
        }
        return url
    }

    @Test func rendersPageAtRetinaResolution() async throws {
        let url = try makeFixturePDF()
        defer { try? FileManager.default.removeItem(at: url) }

        let bookDocument = try #require(BookDocument(url: url))
        let renderer = PageRenderer(bookID: UUID(), document: bookDocument)
        let image = await renderer.image(pageIndex: 0, zoom: 1.0, themeID: "original", screenScale: 2)

        let rendered = try #require(image)
        // Blank PDFPage defaults to US Letter (612×792 pt); zoom 1.0 at 2× scale doubles it.
        #expect(rendered.width == 1224)
        #expect(rendered.height == 1584)
    }

    @Test func cacheReturnsSameImageInstance() async throws {
        let url = try makeFixturePDF()
        defer { try? FileManager.default.removeItem(at: url) }

        let bookDocument = try #require(BookDocument(url: url))
        let renderer = PageRenderer(bookID: UUID(), document: bookDocument)
        let first = await renderer.image(pageIndex: 1, zoom: 1.0, themeID: "original", screenScale: 2)
        let second = await renderer.image(pageIndex: 1, zoom: 1.0, themeID: "original", screenScale: 2)
        #expect(first != nil)
        #expect(first === second)
    }

    @Test func outOfRangePageReturnsNil() async throws {
        let url = try makeFixturePDF()
        defer { try? FileManager.default.removeItem(at: url) }

        let bookDocument = try #require(BookDocument(url: url))
        let renderer = PageRenderer(bookID: UUID(), document: bookDocument)
        let image = await renderer.image(pageIndex: 99, zoom: 1.0, themeID: "original", screenScale: 2)
        #expect(image == nil)
    }

    /// End-to-end guard for "themes only change the background, not the page": a white page
    /// rendered through the full PageRenderer + ThemeCompositor path with a light theme MUST
    /// come out visibly tinted (cream's paper drops the blue channel well below white).
    @Test func lightThemeTintsPagePixelsEndToEnd() async throws {
        let url = try makeFixturePDF()
        defer { try? FileManager.default.removeItem(at: url) }

        let bookDocument = try #require(BookDocument(url: url))
        let renderer = PageRenderer(
            bookID: UUID(),
            document: bookDocument,
            compositor: ThemeCompositor.shared.makeRendererHook()
        )

        func centerPixel(themeID: String) async throws -> (r: Double, g: Double, b: Double) {
            let image = try #require(
                await renderer.image(pageIndex: 0, zoom: 1.0, themeID: themeID, screenScale: 1)
            )
            var px = [UInt8](repeating: 0, count: 4)
            let ctx = try #require(CGContext(
                data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            ctx.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
            return (Double(px[0]) / 255, Double(px[1]) / 255, Double(px[2]) / 255)
        }

        let original = try await centerPixel(themeID: "original")
        #expect(original.b > 0.95, "original should stay near-white")

        let cream = try await centerPixel(themeID: "cream")
        #expect(cream.b < 0.85, "cream page paper must be visibly tinted, got \(cream)")
        #expect(cream.r > cream.b, "cream tint is warm — red should lead blue")

        let sepia = try await centerPixel(themeID: "sepia")
        #expect(sepia.b < 0.75, "sepia page paper must be strongly tinted, got \(sepia)")
    }
}
