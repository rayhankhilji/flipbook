import CoreGraphics
import Testing

@testable import FlipbookCore

@Suite struct ReflowExtractorTests {
    @Test func mergesHardWrappedLines() {
        let pageText = """
        The quick brown fox jumps over the lazy dog while the
        typesetter watches from a distance, noting every letter
        of the alphabet in turn.
        """
        let paragraphs = ReflowExtractor.paragraphs(fromPageText: pageText)
        #expect(paragraphs.count == 1)
        #expect(paragraphs[0].contains("the typesetter watches"))
        #expect(!paragraphs[0].contains("\n"))
    }

    @Test func blankLinesSplitParagraphs() {
        let pageText = "First paragraph line.\n\nSecond paragraph line."
        let paragraphs = ReflowExtractor.paragraphs(fromPageText: pageText)
        #expect(paragraphs.count == 2)
    }

    @Test func rejoinsHyphenatedLineBreaks() {
        let pageText = """
        The reader encountered a beautifully type-
        set paragraph in the middle of the book.
        """
        let paragraphs = ReflowExtractor.paragraphs(fromPageText: pageText)
        #expect(paragraphs.count == 1)
        #expect(paragraphs[0].contains("typeset"))
        #expect(!paragraphs[0].contains("type- set"))
    }

    @Test func shortSentenceEndingLineStartsNewParagraph() {
        let pageText = """
        A long line of continuous prose that runs the full measure of the page here.
        It ends.
        A brand new paragraph begins with fresh ideas and continues along the page
        for a while longer.
        """
        let paragraphs = ReflowExtractor.paragraphs(fromPageText: pageText)
        #expect(paragraphs.count == 2)
        #expect(paragraphs[1].hasPrefix("A brand new paragraph"))
    }

    @Test func blocksCarryPageBreaks() {
        let blocks = ReflowExtractor.blocks(fromPageTexts: ["Page one text.", "Page two text."])
        let pageBreaks = blocks.filter {
            if case .pageBreak = $0.kind { return true }
            return false
        }
        #expect(pageBreaks.count == 2)
        #expect(blocks.first?.kind == .pageBreak(0))
    }
}

