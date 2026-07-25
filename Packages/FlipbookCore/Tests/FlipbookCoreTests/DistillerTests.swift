import Foundation
import Testing

@testable import FlipbookCore

@Suite struct DistillerTests {
    @Test func shortTextStaysOneChunk() {
        let chunks = BookDistiller.chunk("A short book.", size: 1000)
        #expect(chunks.count == 1)
    }

    @Test func longTextSplitsAndLosesNothing() {
        // 300 paragraphs of ~100 chars — several chunks at a 1k budget.
        let paragraphs = (0..<300).map { "Paragraph \($0): " + String(repeating: "x", count: 80) }
        let text = paragraphs.joined(separator: "\n")
        let chunks = BookDistiller.chunk(text, size: 1000)

        #expect(chunks.count > 1)
        // Every chunk stays within budget apart from unavoidable single-paragraph overflow.
        for chunk in chunks {
            #expect(chunk.count <= 1000)
        }
        // Rejoining reproduces the source, so no content is dropped between chunks.
        #expect(chunks.joined(separator: "\n") == text)
    }

    @Test func paragraphLongerThanChunkIsHardSplit() {
        let giant = String(repeating: "y", count: 2500)
        let chunks = BookDistiller.chunk(giant, size: 1000)
        #expect(chunks.count == 3)
        #expect(chunks.joined() == giant)
    }

    @Test func bulkModelIsCheaperTierThanFlagship() {
        // Distillation reads whole books; it must never default to the flagship model.
        for provider in AIProvider.allCases {
            #expect(provider.bulkModelID != provider.defaultModelID)
        }
    }

    @Test func personaPromptCarriesScopeAndCharacterRules() {
        let prompt = AuthorPersonaBuilder.systemPrompt(
            authorName: "Jane Doe",
            profileText: "## Who They Are\nA novelist.",
            digests: [.init(bookTitle: "The Book", digestText: "## Overview\nIt argues things.")],
            scopeBookTitle: "The Book"
        )
        #expect(prompt.contains("You are Jane Doe"))
        #expect(prompt.contains("The Book"))
        #expect(prompt.contains("A novelist"))
        // The persona must not break frame.
        #expect(prompt.contains("never refer to yourself as an AI")
            || prompt.contains("Never refer to yourself as an AI"))
    }
}
