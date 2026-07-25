import Foundation

/// Turns a whole book into a compact, faithful digest an author persona can reason over.
///
/// A 400-page book is roughly 250k–400k tokens. Sending that on every message would be
/// slow and expensive, and most models won't take it at all. So distillation is
/// **map–reduce**:
///
/// 1. **Map** — the book is split into large chunks (~28k characters, well inside every
///    provider's context) and each chunk is summarized *in parallel, bounded* by the
///    provider's cheapest model (`AIProvider.bulkModelID`). This is where nearly all the
///    tokens are spent, which is exactly why it must not run on the flagship model.
/// 2. **Reduce** — the chunk notes (a few thousand tokens total) are composed by the main
///    model into one structured digest: what the book argues, how it unfolds, how the
///    author actually writes, and verbatim lines worth quoting.
///
/// The result is cached as a `BookDigest`, so a book is distilled once and reused forever.
public actor BookDistiller {
    public static let shared = BookDistiller()

    /// Characters per map chunk. ~28k chars ≈ 7k tokens — big enough to keep the call count
    /// (and therefore the fixed per-call overhead) low, small enough for every provider.
    private let chunkCharacters = 28_000

    /// How many chunk summaries run concurrently. Enough to be fast, low enough to stay
    /// clear of provider rate limits on a personal key.
    private let mapConcurrency = 4

    public struct Progress: Sendable {
        public let completedChunks: Int
        public let totalChunks: Int
        public let stage: Stage

        public enum Stage: Sendable { case reading, mapping, composing, done }

        public var fraction: Double {
            guard totalChunks > 0 else { return 0 }
            // Reserve the last 10% for the compose step.
            return min(Double(completedChunks) / Double(totalChunks), 1) * 0.9
        }
    }

    public init() {}

    /// Distills raw page texts into a structured digest.
    /// - Parameter onProgress: called on the main actor as chunks complete, for the UI.
    public func distill(
        pageTexts: [String],
        bookTitle: String,
        authorName: String,
        provider: AIProvider,
        composeModelID: String,
        onProgress: @escaping @Sendable (Progress) -> Void
    ) async throws -> (digest: String, chunkCount: Int, sourceCharacters: Int) {
        let fullText = pageTexts.joined(separator: "\n")
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 500 else {
            throw DistillError.notEnoughText
        }

        let chunks = Self.chunk(trimmed, size: chunkCharacters)
        onProgress(Progress(completedChunks: 0, totalChunks: chunks.count, stage: .mapping))

        // MARK: Map
        var notes = [String?](repeating: nil, count: chunks.count)
        var completed = 0

        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            var next = 0

            func addTask(_ index: Int) {
                let chunk = chunks[index]
                let position = "part \(index + 1) of \(chunks.count)"
                group.addTask { [weak self] in
                    guard let self else { return (index, "") }
                    let text = try await self.summarizeChunk(
                        chunk, position: position, bookTitle: bookTitle,
                        authorName: authorName, provider: provider
                    )
                    return (index, text)
                }
            }

            while next < min(mapConcurrency, chunks.count) {
                addTask(next)
                next += 1
            }
            while let (index, text) = try await group.next() {
                notes[index] = text
                completed += 1
                onProgress(Progress(completedChunks: completed, totalChunks: chunks.count, stage: .mapping))
                if next < chunks.count {
                    addTask(next)
                    next += 1
                }
            }
        }

        // MARK: Reduce
        onProgress(Progress(completedChunks: chunks.count, totalChunks: chunks.count, stage: .composing))
        let digest = try await compose(
            notes: notes.compactMap { $0 }, bookTitle: bookTitle, authorName: authorName,
            provider: provider, modelID: composeModelID
        )
        onProgress(Progress(completedChunks: chunks.count, totalChunks: chunks.count, stage: .done))

        return (digest, chunks.count, trimmed.count)
    }

    // MARK: - Map phase

    private func summarizeChunk(
        _ chunk: String, position: String, bookTitle: String,
        authorName: String, provider: AIProvider
    ) async throws -> String {
        let system = """
        You are a meticulous literary analyst. You are given one part of a book and must \
        produce dense, factual notes that another model will later use to speak *as the \
        author*. Preserve the author's actual claims, reasoning, terminology, and cadence. \
        Never invent content that is not in the excerpt. Be compact — notes, not prose.
        """

        let prompt = """
        Book: "\(bookTitle)"\(authorName.isEmpty ? "" : " by \(authorName)")
        Excerpt: \(position)

        Write notes in exactly these sections, using terse bullets:

        IDEAS: the substantive claims and arguments made here, with the reasoning.
        TERMS: any coined terms, frameworks, or recurring metaphors, each defined briefly.
        QUOTES: up to 4 short verbatim sentences that best capture the author's voice or a key claim. Quote exactly.
        VOICE: 1–2 bullets on how the author writes here (tone, rhythm, address, humour, register).
        BELIEFS: what this excerpt reveals about the author's worldview, values, or convictions.

        Omit a section entirely if the excerpt genuinely contains nothing for it.

        EXCERPT:
        \(chunk)
        """

        return try await AIService.shared.complete(
            provider: provider, system: system, prompt: prompt,
            modelID: provider.bulkModelID, maxTokens: 1200
        )
    }

    // MARK: - Reduce phase

    private func compose(
        notes: [String], bookTitle: String, authorName: String,
        provider: AIProvider, modelID: String
    ) async throws -> String {
        let system = """
        You are building a reference document that will let a model speak convincingly and \
        accurately as the author of a specific book. Work only from the supplied notes. \
        Be specific and substantive — this document replaces the book itself.
        """

        let joined = notes.enumerated()
            .map { "--- NOTES FROM PART \($0.offset + 1) ---\n\($0.element)" }
            .joined(separator: "\n\n")

        let prompt = """
        Compose a reference digest of "\(bookTitle)"\(authorName.isEmpty ? "" : " by \(authorName)") \
        from the sequential notes below.

        Use exactly these sections:

        ## Overview
        What this book is and what it sets out to do, in 3–5 sentences.

        ## Core Arguments
        The book's main claims, in order of importance, each with the author's reasoning. Be thorough — this is the heart of the digest.

        ## How It Unfolds
        The progression of the book from beginning to end, so the persona knows where ideas appear and how they build.

        ## Key Terms
        Coined terms, frameworks, and recurring metaphors, each defined as the author uses them.

        ## Voice
        Precisely how this author writes and speaks: tone, rhythm, sentence shape, how they address the reader, characteristic moves, humour, register.

        ## Worldview
        The convictions, values, and assumptions underlying the book — what this author believes and why.

        ## Quotable Lines
        8–15 of the strongest verbatim quotes from the notes, each on its own line in quotation marks. Reproduce them exactly; do not paraphrase.

        NOTES:
        \(joined)
        """

        return try await AIService.shared.complete(
            provider: provider, system: system, prompt: prompt,
            modelID: modelID, maxTokens: 4000
        )
    }

    // MARK: - Chunking

    /// Splits text into chunks of roughly `size` characters, preferring paragraph breaks so
    /// an argument isn't severed mid-sentence.
    static func chunk(_ text: String, size: Int) -> [String] {
        guard text.count > size else { return [text] }

        var chunks: [String] = []
        var current = ""
        current.reserveCapacity(size)

        for paragraph in text.components(separatedBy: "\n") {
            if current.count + paragraph.count + 1 > size, !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            // A single paragraph longer than a whole chunk (rare) is hard-split.
            if paragraph.count > size {
                var remainder = Substring(paragraph)
                while remainder.count > size {
                    chunks.append(String(remainder.prefix(size)))
                    remainder = remainder.dropFirst(size)
                }
                current = String(remainder)
            } else {
                current += (current.isEmpty ? "" : "\n") + paragraph
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    public enum DistillError: LocalizedError {
        case notEnoughText

        public var errorDescription: String? {
            switch self {
            case .notEnoughText:
                return "This book has no extractable text layer — it may be a scanned PDF. Distillation needs selectable text."
            }
        }
    }
}
