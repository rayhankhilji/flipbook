import CoreGraphics
import Testing

@testable import FlipbookCore

@Suite struct BookSpreadLayoutTests {
    @Test func coverSpreadIsAlone() {
        let pages = BookSpreadLayout.pages(inSpread: 0, pageCount: 10)
        #expect(pages.left == nil)
        #expect(pages.right == 0)
    }

    @Test func interiorSpreadsPairOddEven() {
        let spread1 = BookSpreadLayout.pages(inSpread: 1, pageCount: 10)
        #expect(spread1.left == 1)
        #expect(spread1.right == 2)

        let spread3 = BookSpreadLayout.pages(inSpread: 3, pageCount: 10)
        #expect(spread3.left == 5)
        #expect(spread3.right == 6)
    }

    @Test func trailingOddPageHasNoRightNeighbor() {
        // 4 pages: cover(0), (1,2), (3, —)
        let last = BookSpreadLayout.pages(inSpread: 2, pageCount: 4)
        #expect(last.left == 3)
        #expect(last.right == nil)
    }

    @Test(arguments: [(1, 1), (2, 2), (3, 2), (4, 3), (5, 3), (76, 39)])
    func spreadCounts(pageCount: Int, expected: Int) {
        #expect(BookSpreadLayout.spreadCount(pageCount: pageCount) == expected)
    }

    @Test func spreadContainingPageRoundTrips() {
        for pageIndex in 0..<20 {
            let spread = BookSpreadLayout.spread(containing: pageIndex)
            let pages = BookSpreadLayout.pages(inSpread: spread, pageCount: 20)
            #expect(pages.left == pageIndex || pages.right == pageIndex)
        }
    }

    @Test func committedIndexIsFurthestPage() {
        #expect(BookSpreadLayout.committedIndex(forSpread: 0, pageCount: 10) == 0)
        #expect(BookSpreadLayout.committedIndex(forSpread: 1, pageCount: 10) == 2)
        // Trailing odd page commits the left page.
        #expect(BookSpreadLayout.committedIndex(forSpread: 2, pageCount: 4) == 3)
    }

    @Test func wideWindowProducesSpread() {
        let layout = BookSpreadLayout.compute(
            bounds: CGSize(width: 1400, height: 900),
            spread: 2,
            pageCount: 20,
            pageSize: CGSize(width: 612, height: 792)
        )
        #expect(!layout.isSingle)
        #expect(layout.leftRect.maxX == layout.rightRect.minX)
        #expect(layout.leftRect.width == layout.rightRect.width)
        #expect(layout.bookRect.contains(layout.leftRect))
        #expect(layout.bookRect.contains(layout.rightRect))
    }

    @Test func narrowWindowFallsBackToSinglePage() {
        let layout = BookSpreadLayout.compute(
            bounds: CGSize(width: 700, height: 900),
            spread: 2,
            pageCount: 20,
            pageSize: CGSize(width: 612, height: 792)
        )
        #expect(layout.isSingle)
    }
}
