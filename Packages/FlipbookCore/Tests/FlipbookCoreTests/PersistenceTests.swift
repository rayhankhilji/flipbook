import Foundation
import SwiftData
import Testing

@testable import FlipbookCore

@Suite @MainActor struct PersistenceTests {
    @Test func settingsSingletonCreatedOnce() throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let context = container.mainContext
        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        #expect(settings.count == 1)
        #expect(settings.first?.selectedThemeID == "warmPaper")
    }

    @Test func deletingBookCascadesToAnnotations() throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let context = container.mainContext

        let book = Book(
            title: "Test",
            pageCount: 10,
            fileBookmarkData: Data(),
            lastKnownPath: "/tmp/test.pdf",
            fileSizeBytes: 100
        )
        context.insert(book)

        let bookmark = Bookmark(book: book, pageIndex: 3)
        let highlight = Highlight(book: book, pageIndex: 5, kind: .region, quadPointsData: Data(), colorTag: "yellow")
        let progress = ReadingProgress(book: book, currentPageIndex: 4)
        context.insert(bookmark)
        context.insert(highlight)
        context.insert(progress)
        try context.save()

        context.delete(book)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Bookmark>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Highlight>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ReadingProgress>()).isEmpty)
    }

    @Test func readingProgressPersistsPosition() throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let context = container.mainContext

        let book = Book(
            title: "Positioned",
            pageCount: 200,
            fileBookmarkData: Data(),
            lastKnownPath: "/tmp/p.pdf",
            fileSizeBytes: 1
        )
        context.insert(book)
        let progress = ReadingProgress(book: book, currentPageIndex: 42, zoomLevel: 1.5)
        context.insert(progress)
        book.progress = progress
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Book>()).first
        #expect(fetched?.progress?.currentPageIndex == 42)
        #expect(fetched?.progress?.zoomLevel == 1.5)
    }
}
