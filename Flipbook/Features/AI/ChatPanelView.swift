import FlipbookCore
import FlipbookDesignSystem
import SwiftUI

/// The reader's AI companion panel: a header with a conversation menu, a transcript of
/// grey user bubbles and plain-Markdown assistant replies, and a rounded input pill with a
/// circular send/stop control. Deliberately unbubbly on the assistant side — replies read
/// as typeset prose, not chat-app chrome.
struct ChatPanelView: View {
    @Bindable var chat: BookChatModel
    let onClose: () -> Void

    @FocusState private var inputFocused: Bool
    private let bottomAnchor = "chat-bottom"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            transcript
            if let error = chat.errorMessage {
                errorBar(error)
            }
            inputBar
        }
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { inputFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: SpacingTokens.sm) {
            Menu {
                Button {
                    chat.reset()
                } label: {
                    Label("New Conversation", systemImage: "square.and.pencil")
                }
                Divider()
                Text(chat.activeModelLabel)
            } label: {
                HStack(spacing: 4) {
                    Text(chat.isEmpty ? "New conversation" : "Conversation")
                        .font(.system(.headline))
                        .foregroundStyle(ColorTokens.chromeText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ColorTokens.chromeSecondaryText)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()

            circleIconButton("square.and.pencil", help: "New Conversation") { chat.reset() }
            circleIconButton("xmark", help: "Close") { onClose() }
        }
        .padding(.horizontal, SpacingTokens.md)
        .padding(.vertical, SpacingTokens.sm + 2)
    }

    private func circleIconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ColorTokens.chromeSecondaryText)
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SpacingTokens.lg) {
                    if chat.isEmpty {
                        emptyState.padding(.top, SpacingTokens.xl)
                    } else {
                        ForEach(chat.messages) { message in
                            messageRow(message).id(message.id)
                        }
                        if chat.isStreaming, chat.messages.last?.text.isEmpty == true {
                            TypingIndicator()
                        }
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(.horizontal, SpacingTokens.md)
                .padding(.vertical, SpacingTokens.md)
            }
            .onChange(of: chat.messages.last?.text) { _, _ in scrollToBottom(proxy) }
            .onChange(of: chat.messages.count) { _, _ in scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }

    @ViewBuilder
    private func messageRow(_ message: AIChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(.body))
                    .foregroundStyle(ColorTokens.chromeText)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Color.primary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }
        case .assistant:
            MarkdownText(markdown: message.text)
                .foregroundStyle(ColorTokens.chromeText)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: SpacingTokens.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(BrandTokens.emberGradient)

            VStack(spacing: 3) {
                Text("Ask about this book")
                    .font(TypographyTokens.bookTitle)
                    .foregroundStyle(ColorTokens.chromeText)
                Text(chat.bookTitle)
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.chromeSecondaryText)
                    .lineLimit(1)
            }

            if chat.isConfigured {
                VStack(spacing: SpacingTokens.sm) {
                    ForEach(chat.suggestions, id: \.self) { suggestion in
                        Button {
                            chat.send(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(.system(.callout))
                                .foregroundStyle(ColorTokens.chromeText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    Color.primary.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(ColorTokens.chromeSeparator.opacity(0.5), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, SpacingTokens.sm)
            } else {
                setupPrompt.padding(.top, SpacingTokens.sm)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var setupPrompt: some View {
        VStack(spacing: SpacingTokens.sm) {
            Text("Add an AI provider key to start chatting.")
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.chromeSecondaryText)
                .multilineTextAlignment(.center)
            SettingsLink {
                Label("Set Up AI", systemImage: "gearshape")
            }
            .buttonStyle(.flipbook(prominent: true))
        }
    }

    // MARK: - Error

    private func errorBar(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.chromeSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, SpacingTokens.md)
        .padding(.vertical, SpacingTokens.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: SpacingTokens.sm) {
            TextField("Ask about this book…", text: $chat.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(.body))
                .lineLimit(1...6)
                .focused($inputFocused)
                .disabled(!chat.isConfigured)
                .onSubmit(send)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.primary.opacity(0.05)))
                .overlay(
                    Capsule().strokeBorder(ColorTokens.chromeSeparator.opacity(0.6), lineWidth: 0.5)
                )

            sendButton
        }
        .padding(.horizontal, SpacingTokens.md)
        .padding(.top, SpacingTokens.sm)
        .padding(.bottom, SpacingTokens.md)
    }

    private var sendButton: some View {
        Button {
            if chat.isStreaming { chat.stop() } else { send() }
        } label: {
            ZStack {
                Circle().fill(sendButtonColor)
                Image(systemName: chat.isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(!sendEnabled)
        .help(chat.isStreaming ? "Stop" : "Send")
    }

    private var sendButtonColor: Color {
        sendEnabled ? Color.accentColor : Color.secondary.opacity(0.35)
    }

    private var sendEnabled: Bool {
        chat.isStreaming || (chat.isConfigured && !chat.draft.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func send() {
        chat.send(chat.draft)
    }
}

/// Three pulsing dots shown while the assistant prepares its first token.
private struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(animating ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}
