import FlipbookCore
import FlipbookDesignSystem
import SwiftUI

/// A conversation with an author persona. Wider and calmer than the reader's side panel —
/// the author's words are the page here, so they get generous measure, serif type, and no
/// bubble around them.
struct AuthorChatView: View {
    @Bindable var chat: AuthorChatModel
    let onNewConversation: () -> Void

    @FocusState private var inputFocused: Bool
    private let bottomAnchor = "author-chat-bottom"

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(ColorTokens.creamHairline.opacity(0.35)).frame(height: 1)
            transcript
            if let preparation = chat.preparation {
                preparationBar(preparation)
            }
            if let error = chat.errorMessage {
                errorBar(error)
            }
            inputBar
        }
        .background(ColorTokens.canvas)
        .onAppear { inputFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: SpacingTokens.sm) {
            AuthorAvatar(name: chat.authorName, size: 30)

            VStack(alignment: .leading, spacing: 0) {
                Text(chat.authorName)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(ColorTokens.ink)
                Text(chat.scopeLabel)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.inkSecondary)
                    .lineLimit(1)
            }

            Spacer()

            scopeMenu

            Button(action: onNewConversation) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ColorTokens.inkSecondary)
                    .frame(width: 28, height: 28)
                    .background(ColorTokens.cream.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain)
            .help("New Conversation")
        }
        .padding(.horizontal, SpacingTokens.lg)
        .padding(.vertical, SpacingTokens.sm + 2)
    }

    /// Chooses what the author may draw on: everything they wrote, or one specific book.
    private var scopeMenu: some View {
        Menu {
            Button {
                chat.scope = .allBooks
            } label: {
                if case .allBooks = chat.scope {
                    Label("All their books", systemImage: "checkmark")
                } else {
                    Text("All their books")
                }
            }
            Divider()
            ForEach(chat.books) { book in
                Button {
                    chat.scope = .book(book.id)
                } label: {
                    if case .book(let id) = chat.scope, id == book.id {
                        Label(book.title, systemImage: "checkmark")
                    } else {
                        Text(book.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 11, weight: .semibold))
                Text("Reference")
                    .font(TypographyTokens.caption)
            }
            .foregroundStyle(ColorTokens.inkSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose which of their books this conversation draws on")
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: SpacingTokens.lg) {
                    if chat.isEmpty {
                        emptyState.padding(.top, SpacingTokens.xl)
                    } else {
                        ForEach(chat.messages) { message in
                            messageRow(message).id(message.id)
                        }
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, SpacingTokens.xl)
                .padding(.vertical, SpacingTokens.lg)
            }
            .onChange(of: chat.messages.last?.text) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
            }
            .onChange(of: chat.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: AIChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 80)
                Text(message.text)
                    .font(.system(.body))
                    .foregroundStyle(ColorTokens.ink)
                    .textSelection(.enabled)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .background(
                        ColorTokens.cream.opacity(0.75),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }
        case .assistant:
            // The author speaks in serif, unbubbled — like a letter, not a chat app.
            MarkdownText(markdown: message.text)
                .font(.system(.body, design: .serif))
                .foregroundStyle(ColorTokens.ink)
                .lineSpacing(3)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.md) {
            HStack(spacing: SpacingTokens.sm) {
                AuthorAvatar(name: chat.authorName, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.authorName)
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .foregroundStyle(ColorTokens.ink)
                    Text(chat.scopeLabel)
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.inkSecondary)
                }
            }

            if chat.isConfigured {
                Text("Ask them anything — their ideas, their advice, what they were really getting at.")
                    .font(TypographyTokens.body)
                    .foregroundStyle(ColorTokens.inkSecondary)

                VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                    ForEach(chat.suggestions, id: \.self) { suggestion in
                        Button {
                            chat.send(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(.system(.callout))
                                .foregroundStyle(ColorTokens.ink)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(ColorTokens.cream.opacity(0.4))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(ColorTokens.creamHairline.opacity(0.4), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, SpacingTokens.xs)

                Text("The first message takes a moment — their books are read and distilled once, then remembered.")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.inkSecondary.opacity(0.8))
            } else {
                Text("Add an AI provider key to talk with authors.")
                    .font(TypographyTokens.body)
                    .foregroundStyle(ColorTokens.inkSecondary)
                SettingsLink {
                    Label("Set Up AI", systemImage: "gearshape")
                }
                .buttonStyle(.flipbook(prominent: true))
            }
        }
    }

    // MARK: - Status bars

    private func preparationBar(_ state: AuthorChatModel.PreparationState) -> some View {
        HStack(spacing: SpacingTokens.sm) {
            ProgressView().controlSize(.small)
            Text(state.label)
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.inkSecondary)
            Spacer()
            if let fraction = state.fraction, fraction > 0 {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
            }
        }
        .padding(.horizontal, SpacingTokens.lg)
        .padding(.vertical, SpacingTokens.sm)
        .background(ColorTokens.cream.opacity(0.35))
    }

    private func errorBar(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message)
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, SpacingTokens.lg)
        .padding(.vertical, SpacingTokens.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: SpacingTokens.sm) {
            TextField("Say something to \(chat.authorName)…", text: $chat.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(.body))
                .lineLimit(1...6)
                .focused($inputFocused)
                .disabled(!chat.isConfigured)
                .onSubmit { chat.send(chat.draft) }
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(Capsule().fill(ColorTokens.cream.opacity(0.45)))
                .overlay(Capsule().strokeBorder(ColorTokens.creamHairline.opacity(0.45), lineWidth: 0.5))

            Button {
                if chat.isStreaming { chat.stop() } else { chat.send(chat.draft) }
            } label: {
                ZStack {
                    Circle().fill(sendColor)
                    Image(systemName: chat.isStreaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .disabled(!sendEnabled)
            .help(chat.isStreaming ? "Stop" : "Send")
        }
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, SpacingTokens.xl)
        .padding(.vertical, SpacingTokens.md)
    }

    private var sendEnabled: Bool {
        chat.isStreaming || (chat.isConfigured && !chat.draft.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var sendColor: Color {
        sendEnabled ? ColorTokens.espresso : ColorTokens.inkSecondary.opacity(0.35)
    }
}
