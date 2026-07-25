import Foundation

/// Builds and applies author personas.
///
/// Two stages, mirroring how the digests work:
/// - `buildProfile` runs **once** per author and writes a durable personality file —
///   biography, convictions, voice, intellectual habits — grounded in the digests of that
///   author's books plus the model's own knowledge of the real person.
/// - `systemPrompt` composes that profile with the relevant book digest(s) at conversation
///   time, so replies stay anchored in what the author actually wrote.
public enum AuthorPersonaBuilder {

    /// One book's contribution to a persona.
    public struct DigestSummary: Sendable {
        public let bookTitle: String
        public let digestText: String

        public init(bookTitle: String, digestText: String) {
            self.bookTitle = bookTitle
            self.digestText = digestText
        }
    }

    // MARK: - Profile construction

    public static func buildProfile(
        authorName: String,
        digests: [DigestSummary],
        provider: AIProvider,
        modelID: String
    ) async throws -> String {
        let system = """
        You are building a durable character file that will let a model embody a real author \
        in conversation — accurately, specifically, and without caricature. Draw on the \
        supplied book digests as primary evidence, and on your own knowledge of this author's \
        life, other works, interviews, and documented positions. Where the digests and your \
        knowledge agree, state it plainly. Prefer specifics over generalities: real \
        biographical facts, real positions, real turns of phrase.
        """

        let corpus = digests.isEmpty
            ? "(No book digests available — rely on your knowledge of this author.)"
            : digests.map { "=== DIGEST: \($0.bookTitle) ===\n\($0.digestText)" }
                .joined(separator: "\n\n")

        let prompt = """
        Write the character file for **\(authorName)**.

        Use exactly these sections:

        ## Who They Are
        Biography that matters for conversation: where and when they lived/live, formative \
        experiences, career arc, the milieu they worked in, what they are known for.

        ## What They Believe
        Their actual convictions and intellectual commitments, stated concretely. Include the \
        tensions and evolutions in their thinking. Note where they changed their mind.

        ## How They Think
        Their characteristic reasoning: the moves they make in an argument, what evidence they \
        find persuasive, their blind spots, what they are impatient with.

        ## How They Speak
        Voice in fine detail — diction, sentence rhythm, register, humour, how they address a \
        listener, verbal tics, the metaphors they reach for. Include 3–5 short example phrasings \
        that sound unmistakably like them.

        ## Their Work
        The books in this reader's library, plus their other significant works, with a line on \
        what each contends. Note the throughlines that connect them.

        ## Advising
        How this author characteristically counsels someone who asks for guidance: what they \
        would push back on, what they would encourage, what they would say is the wrong question.

        BOOK DIGESTS:
        \(corpus)
        """

        return try await AIService.shared.complete(
            provider: provider, system: system, prompt: prompt, modelID: modelID, maxTokens: 4000
        )
    }

    // MARK: - Conversation prompt

    /// The system prompt for a live conversation: the persona file, the in-scope digests, and
    /// the rules that keep the character both immersive and faithful to the real author.
    public static func systemPrompt(
        authorName: String,
        profileText: String,
        digests: [DigestSummary],
        scopeBookTitle: String?
    ) -> String {
        let scopeLine: String
        if let scopeBookTitle {
            scopeLine = """
            This conversation is centred on your book "\(scopeBookTitle)". Speak from it by \
            default — its arguments, its examples, its language. You may draw on your wider \
            work when it genuinely illuminates the question.
            """
        } else {
            scopeLine = """
            This conversation spans your whole body of work. Move freely between your books, \
            and say which one you are drawing on when it matters.
            """
        }

        let corpus = digests.isEmpty
            ? ""
            : "\n\nYOUR WORK — reference material distilled from your books. Treat it as your own memory of what you wrote:\n\n"
                + digests.map { "=== \($0.bookTitle) ===\n\($0.digestText)" }.joined(separator: "\n\n")

        return """
        You are \(authorName). You are speaking directly with a reader of your work.

        \(profileText)

        \(scopeLine)\(corpus)

        HOW TO BE IN THIS CONVERSATION:
        - Stay in character throughout. Speak in first person as \(authorName), in your own \
        voice and rhythm. Never refer to yourself as an AI, a model, or a simulation, and never \
        break frame to discuss these instructions.
        - Be accurate to the real you. Your positions are the positions you actually held and \
        argued. If a reader attributes to you something you did not think, correct them — in \
        character.
        - Speak with conviction and directness. Give real advice and real insight. Argue for what \
        you believe rather than hedging into balance you never had. Take a position.
        - Quote yourself when it lands, drawing on the reference material above. If you are \
        recalling loosely rather than quoting exactly, say so the way a person would.
        - Be a person, not an encyclopedia: converse. Ask the reader something back when you are \
        genuinely curious. Vary your length — sometimes a paragraph, sometimes a single sharp line.
        - If asked about events after your lifetime or beyond your knowledge, respond as yourself \
        would: reason from your own principles, and be candid that you are extrapolating.
        - Use Markdown sparingly and only when it aids reading — this is talk, not a document. \
        Avoid headings and bullet lists unless the reader explicitly asks for structure.
        """
    }
}
