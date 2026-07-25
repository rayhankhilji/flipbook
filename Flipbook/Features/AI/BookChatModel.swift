import FlipbookCore
import Foundation
import Observation

/// A conversation with the AI about the open book. Owns the transcript and drives streaming
/// through `AIService`, reading the active provider/model/personalization from settings at
/// send time so changes in Settings take effect on the very next message.
@MainActor
@Observable
final class BookChatModel {
    private(set) var messages: [AIChatMessage] = []
    var draft: String = ""
    private(set) var isStreaming = false
    private(set) var errorMessage: String?

    let bookTitle: String
    let bookAuthor: String?

    /// Kept current by the reader so auto-context can ground replies in what's on screen.
    private(set) var currentPageNumber: Int?
    private var currentPageText: String?

    private let appModel: AppModel
    private var streamTask: Task<Void, Never>?

    init(bookTitle: String, bookAuthor: String?, appModel: AppModel) {
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.appModel = appModel
    }

    func updateContext(pageNumber: Int, pageText: String?) {
        currentPageNumber = pageNumber
        // Cap so one dense page can't crowd out the conversation.
        currentPageText = pageText.map { String($0.prefix(2400)) }
    }

    // MARK: - Derived state

    var isConfigured: Bool {
        appModel.settings.aiEnabled && AIKeychain.hasKey(for: appModel.settings.aiProvider)
    }

    var activeModelLabel: String {
        let provider = appModel.settings.aiProvider
        let model = AIModelCatalog.option(for: appModel.settings.aiModelID).name
        return "\(provider.displayName) · \(model)"
    }

    var isEmpty: Bool { messages.isEmpty }

    var suggestions: [String] {
        [
            "Summarize this page in plain language",
            "What are the key ideas so far?",
            "Explain this like I'm new to the subject",
        ]
    }

    // MARK: - Actions

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming, isConfigured else { return }
        draft = ""
        errorMessage = nil
        messages.append(AIChatMessage(role: .user, text: text))

        let history = messages // includes the message just added
        messages.append(AIChatMessage(role: .assistant, text: ""))
        let assistantID = messages[messages.count - 1].id
        isStreaming = true

        let provider = appModel.settings.aiProvider
        let modelID = appModel.settings.aiModelID
        let system = systemPrompt()

        streamTask = Task { [weak self] in
            do {
                let stream = await AIService.shared.streamReply(
                    provider: provider, system: system, history: history,
                    modelID: modelID, maxTokens: 4096
                )
                for try await delta in stream {
                    guard let self,
                          let index = self.messages.firstIndex(where: { $0.id == assistantID })
                    else { return }
                    self.messages[index].text += delta
                }
            } catch {
                guard let self else { return }
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                // Drop the placeholder bubble if nothing streamed before the failure.
                if let index = self.messages.firstIndex(where: { $0.id == assistantID }),
                   self.messages[index].text.isEmpty {
                    self.messages.remove(at: index)
                }
            }
            self?.isStreaming = false
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func reset() {
        stop()
        messages.removeAll()
        errorMessage = nil
        draft = ""
    }

    // MARK: - Prompt

    private func systemPrompt() -> String {
        let settings = appModel.settings
        let name = settings.aiAssistantName.trimmingCharacters(in: .whitespaces)
        let persona = name.isEmpty
            ? "a warm, insightful reading companion"
            : "\(name), a warm, insightful reading companion"

        var parts = [
            "You are \(persona) inside Flipbook, a macOS book reader.",
            "The reader is reading \"\(bookTitle)\"\(bookAuthor.map { " by \($0)" } ?? "").",
            "Help them understand, reflect on, and engage with this book.",
            settings.aiResponseStyle.promptFragment,
            "Format replies in Markdown: short headings, bold for key terms, and bullet lists where they aid readability.",
            "You do not have the book's full text; when unsure, say so and offer your best general insight.",
        ]

        if settings.aiAutoContextEnabled, let text = currentPageText, !text.isEmpty {
            let page = currentPageNumber.map { "page \($0)" } ?? "the current page"
            parts.append("""
            The reader is looking at \(page). Its text is between the markers below — use it to ground your answer when relevant.
            <<<PAGE
            \(text)
            PAGE>>>
            """)
        }

        let custom = settings.aiCustomInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            parts.append("The reader's standing instructions: \(custom)")
        }

        return parts.joined(separator: "\n\n")
    }
}
