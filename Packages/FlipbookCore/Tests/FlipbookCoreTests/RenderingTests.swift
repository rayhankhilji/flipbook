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
}
