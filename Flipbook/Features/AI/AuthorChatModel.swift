import FlipbookCore
import Foundation
import Observation
import SwiftData

/// Drives one author-persona conversation: makes sure the author's books are distilled and
/// their persona is built (both cached), then streams replies in character and persists the
/// transcript so threads survive relaunches.
@MainActor
@Observable
final class AuthorChatModel {
    /// What the persona is allowed to draw on.
    enum Scope: Hashable {
        case allBooks
        case book(UUID)
    }

    let authorName: String
    /// Every book by this author in the library.
    private(set) var books: [Book]

    var scope: Scope = .allBooks {
        didSet { if scope != oldValue { persistScope() } }
    }

    private(set) var messages: [AIChatMessage] = []
    var draft = ""
    private(set) var isStreaming = false
    private(set) var errorMessage: String?

    /// Non-nil while the author's material is being prepared for the first time.
    private(set) var preparation: PreparationState?

    struct PreparationState {
        var label: String
        var fraction: Double?
    }

    private let appModel: AppModel
    private let modelContext: ModelContext
    private var conversation: AuthorConversation
    private var streamTask: Task<Void, Never>?
    private var cachedSystemPrompt: String?

    init(authorName: String, books: [Book], conversation: AuthorConversation, appModel: AppModel, modelContext: ModelContext) {
        self.authorName = authorName
        self.books = books
        self.conversation = conversation
        self.appModel = appModel
        self.modelContext = modelContext
        self.messages = conversation.messages
        if let scopeID = conversation.scopeBookID {
            self.scope = .book(scopeID)
        }
    }

    // MARK: - Derived state

    var isConfigured: Bool {
        appModel.settings.aiEnabled && AIKeychain.hasKey(for: appModel.settings.aiProvider)
    }

    /// Identifies the backing thread, so the sidebar can mark which one is open.
    var conversationID: UUID { conversation.id }

    var isEmpty: Bool { messages.isEmpty }

    var scopeLabel: String {
        switch scope {
        case .allBooks:
            return books.count == 1 ? books[0].title : "All \(books.count) books"
        case .book(let id):
            return books.first(where: { $0.id == id })?.title ?? "Book"
        }
    }

    var suggestions: [String] {
        [
            "What's the one idea from this you'd want me to actually live by?",
            "Where do you think most readers misunderstand you?",
            "I'm stuck on something — can I ask your advice?",
        ]
    }

    /// Books currently in scope.
    private var scopedBooks: [Book] {
        switch scope {
        case .allBooks: return books
        case .book(let id): return books.filter { $0.id == id }
        }
    }

    // MARK: - Sending

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming, isConfigured else { return }
        draft = ""
        errorMessage = nil

        messages.append(AIChatMessage(role: .user, text: text))
        let history = messages
        messages.append(AIChatMessage(role: .assistant, text: ""))
        let assistantID = messages[messages.count - 1].id
        isStreaming = true
        persistTranscript()

        let provider = appModel.settings.aiProvider
        let modelID = appModel.settings.aiModelID

        streamTask = Task { [weak self] in
            do {
                guard let self else { return }
                let system = try await self.resolveSystemPrompt()
                let stream = await AIService.shared.streamReply(
                    provider: provider, system: system, history: history,
                    modelID: modelID, maxTokens: 4096
                )
                for try await delta in stream {
                    guard let index = self.messages.firstIndex(where: { $0.id == assistantID }) else { return }
                    self.messages[index].text += delta
                }
            } catch {
                guard let self else { return }
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if let index = self.messages.firstIndex(where: { $0.id == assistantID }),
                   self.messages[index].text.isEmpty {
                    self.messages.remove(at: index)
                }
            }
            self?.isStreaming = false
            self?.preparation = nil
            self?.persistTranscript()
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        persistTranscript()
    }

    // MARK: - Preparation (distill → persona → prompt)

    /// Ensures every in-scope book is distilled and the persona exists, then composes the
    /// system prompt. Cached in memory for the session and on disk across launches.
    private func resolveSystemPrompt() async throws -> String {
        if let cachedSystemPrompt { return cachedSystemPrompt }

        let provider = appModel.settings.aiProvider
        let composeModel = appModel.settings.aiModelID
        let scoped = scopedBooks

        // 1. Distill any book that has no fresh digest.
        var digests: [AuthorPersonaBuilder.DigestSummary] = []
        for (offset, book) in scoped.enumerated() {
            if let existing = digest(for: book.id), !existing.isStale {
                digests.append(.init(bookTitle: existing.bookTitle, digestText: existing.digestText))
                continue
            }
            preparation = PreparationState(
                label: scoped.count > 1
                    ? "Reading \(book.title) (\(offset + 1) of \(scoped.count))…"
                    : "Reading \(book.title)…",
                fraction: 0
            )
            if let made = try await distill(book: book, provider: provider, composeModel: composeModel) {
                digests.append(made)
            }
        }

        // 2. Build the persona once, from whatever digests exist.
        let persona: AuthorPersona
        if let existing = personaRecord(), !existing.isStale,
           Set(existing.sourceBookIDs) == Set(books.map(\.id)) {
            persona = existing
        } else {
            preparation = PreparationState(label: "Getting to know \(authorName)…", fraction: nil)
            let allDigests = books.compactMap { book -> AuthorPersonaBuilder.DigestSummary? in
                guard let d = digest(for: book.id) else { return nil }
                return .init(bookTitle: d.bookTitle, digestText: d.digestText)
            }
            let profile = try await AuthorPersonaBuilder.buildProfile(
                authorName: authorName,
                digests: allDigests.isEmpty ? digests : allDigests,
                provider: provider,
                modelID: composeModel
            )
            if let existing = personaRecord() {
                existing.profileText = profile
                existing.sourceBookIDs = books.map(\.id)
                existing.updatedAt = .now
                existing.formatVersion = AuthorPersona.currentFormatVersion
                persona = existing
            } else {
                let created = AuthorPersona(
                    displayName: authorName, profileText: profile,
                    sourceBookIDs: books.map(\.id),
                    modelID: composeModel, providerRaw: provider.rawValue
                )
                modelContext.insert(created)
                persona = created
            }
            try? modelContext.save()
        }

        preparation = nil
        let scopeTitle: String? = {
            if case .book(let id) = scope { return books.first(where: { $0.id == id })?.title }
            return nil
        }()

        let prompt = AuthorPersonaBuilder.systemPrompt(
            authorName: authorName,
            profileText: persona.profileText,
            digests: digests,
            scopeBookTitle: scopeTitle
        )
        cachedSystemPrompt = prompt
        return prompt
    }

    private func distill(
        book: Book, provider: AIProvider, composeModel: String
    ) async throws -> AuthorPersonaBuilder.DigestSummary? {
        // Open the document off the main actor's critical path and pull its text.
        let resolution = FileRelocationResolver.resolve(bookmarkData: book.fileBookmarkData)
        guard let url = resolution.url, let document = BookDocument(url: url) else { return nil }
        let renderer = PageRenderer(bookID: book.id, document: document)
        let pageTexts = await renderer.extractPageTexts()

        // `Book` is a SwiftData model and not Sendable — pull the values the progress
        // callback needs before crossing into the concurrent distiller.
        let bookID = book.id
        let title = book.title

        let result = try await BookDistiller.shared.distill(
            pageTexts: pageTexts,
            bookTitle: title,
            authorName: authorName,
            provider: provider,
            composeModelID: composeModel
        ) { [weak self] progress in
            Task { @MainActor in
                guard let self else { return }
                let label = progress.stage == .composing
                    ? "Composing notes on \(title)…"
                    : "Reading \(title)…"
                self.preparation = PreparationState(label: label, fraction: progress.fraction)
            }
        }

        let record = BookDigest(
            bookID: bookID, bookTitle: title, authorName: authorName,
            digestText: result.digest, sourceCharacterCount: result.sourceCharacters,
            chunkCount: result.chunkCount, modelID: composeModel, providerRaw: provider.rawValue
        )
        modelContext.insert(record)
        try? modelContext.save()
        return .init(bookTitle: title, digestText: result.digest)
    }

    // MARK: - Persistence

    private func digest(for bookID: UUID) -> BookDigest? {
        let descriptor = FetchDescriptor<BookDigest>(predicate: #Predicate { $0.bookID == bookID })
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func personaRecord() -> AuthorPersona? {
        let key = AuthorPersona.normalize(authorName)
        let descriptor = FetchDescriptor<AuthorPersona>(predicate: #Predicate { $0.normalizedName == key })
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func persistTranscript() {
        conversation.messages = messages
        conversation.retitleFromFirstMessage()
        try? modelContext.save()
    }

    private func persistScope() {
        // Scope drives the prompt, so a change invalidates the cached one.
        cachedSystemPrompt = nil
        switch scope {
        case .allBooks:
            conversation.scopeBookID = nil
            conversation.scopeBookTitle = nil
        case .book(let id):
            conversation.scopeBookID = id
            conversation.scopeBookTitle = books.first(where: { $0.id == id })?.title
        }
        try? modelContext.save()
    }
}
