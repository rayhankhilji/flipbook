import FlipbookCore
import FlipbookDesignSystem
import SwiftData
import SwiftUI

/// The Authors surface: every author in the library on the left, and the selected author's
/// conversations on the right. Talking to an author distils their books once (cheaply, with
/// the bulk model) and builds a durable persona, both cached thereafter.
struct AuthorsView: View {
    let books: [Book]

    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AuthorConversation.updatedAt, order: .reverse) private var conversations: [AuthorConversation]

    @State private var selectedAuthor: String?
    @State private var activeChat: AuthorChatModel?

    /// Authors that have a usable name, with their books, most-stocked first.
    private var authors: [(name: String, books: [Book])] {
        Dictionary(grouping: books.filter { !($0.authorHint ?? "").trimmingCharacters(in: .whitespaces).isEmpty }) {
            $0.authorHint!.trimmingCharacters(in: .whitespaces)
        }
        .map { (name: $0.key, books: $0.value) }
        .sorted { lhs, rhs in
            lhs.books.count == rhs.books.count
                ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                : lhs.books.count > rhs.books.count
        }
    }

    var body: some View {
        Group {
            if authors.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    authorList
                        .frame(width: 260)
                    Rectangle()
                        .fill(ColorTokens.creamHairline.opacity(0.35))
                        .frame(width: 1)
                    detail
                }
            }
        }
        .background(ColorTokens.canvas)
    }

    // MARK: - Author list

    private var authorList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                Text("Authors")
                    .font(TypographyTokens.bookTitleLarge)
                    .foregroundStyle(ColorTokens.ink)
                    .padding(.horizontal, SpacingTokens.md)
                    .padding(.top, SpacingTokens.lg)

                Text("Speak with the people behind your books.")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.inkSecondary)
                    .padding(.horizontal, SpacingTokens.md)
                    .padding(.bottom, SpacingTokens.sm)

                ForEach(authors, id: \.name) { author in
                    authorRow(author)
                    // The selected author expands to show their saved threads.
                    if selectedAuthor == author.name {
                        conversationList(for: author.name)
                    }
                }
            }
            .padding(.bottom, SpacingTokens.lg)
        }
        .background(ColorTokens.sidebarSurface.opacity(0.5))
    }

    private func authorRow(_ author: (name: String, books: [Book])) -> some View {
        Button {
            select(author.name)
        } label: {
            HStack(spacing: SpacingTokens.sm) {
                AuthorAvatar(name: author.name)
                VStack(alignment: .leading, spacing: 1) {
                    Text(author.name)
                        .font(.system(.body, design: .serif).weight(.medium))
                        .foregroundStyle(ColorTokens.ink)
                        .lineLimit(1)
                    Text(author.books.count == 1 ? "1 book" : "\(author.books.count) books")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SpacingTokens.sm)
            .padding(.vertical, SpacingTokens.sm)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selectedAuthor == author.name ? ColorTokens.cream.opacity(0.7) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, SpacingTokens.sm)
    }

    /// Saved threads for one author, plus a way to start a fresh one.
    @ViewBuilder
    private func conversationList(for name: String) -> some View {
        let key = AuthorPersona.normalize(name)
        let threads = conversations.filter { $0.authorNormalizedName == key }

        VStack(alignment: .leading, spacing: 1) {
            ForEach(threads) { thread in
                Button {
                    open(thread, authorName: name)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 9))
                            .foregroundStyle(ColorTokens.inkSecondary.opacity(0.7))
                        Text(thread.title)
                            .font(TypographyTokens.caption)
                            .foregroundStyle(
                                activeChat?.conversationID == thread.id
                                    ? ColorTokens.ink
                                    : ColorTokens.inkSecondary
                            )
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, SpacingTokens.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(activeChat?.conversationID == thread.id
                                  ? ColorTokens.cream.opacity(0.5) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete Conversation", role: .destructive) {
                        delete(thread)
                    }
                }
            }

            Button {
                startConversation(with: name, fresh: true)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                    Text("New conversation")
                        .font(TypographyTokens.caption)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(ColorTokens.inkSecondary.opacity(0.85))
                .padding(.vertical, 4)
                .padding(.horizontal, SpacingTokens.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, SpacingTokens.lg + SpacingTokens.sm)
        .padding(.trailing, SpacingTokens.sm)
        .padding(.bottom, SpacingTokens.xs)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let chat = activeChat {
            AuthorChatView(chat: chat, onNewConversation: { startConversation(with: chat.authorName, fresh: true) })
                .id(ObjectIdentifier(chat))
        } else {
            VStack(spacing: SpacingTokens.md) {
                Image(systemName: "person.and.background.dotted")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(ColorTokens.inkSecondary.opacity(0.6))
                Text("Choose an author to begin")
                    .font(TypographyTokens.headline)
                    .foregroundStyle(ColorTokens.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: SpacingTokens.md) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(BrandTokens.emberGradient)
            Text("No authors yet")
                .font(TypographyTokens.bookTitleLarge)
                .foregroundStyle(ColorTokens.ink)
            Text("Books need an author name before you can talk to them. Add one with Get Info on any book.")
                .font(TypographyTokens.body)
                .foregroundStyle(ColorTokens.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func select(_ name: String) {
        selectedAuthor = name
        startConversation(with: name, fresh: false)
    }

    /// Reopens an existing thread.
    private func open(_ thread: AuthorConversation, authorName name: String) {
        selectedAuthor = name
        activeChat = AuthorChatModel(
            authorName: name,
            books: authors.first(where: { $0.name == name })?.books ?? [],
            conversation: thread,
            appModel: appModel,
            modelContext: modelContext
        )
    }

    private func delete(_ thread: AuthorConversation) {
        if activeChat?.conversationID == thread.id { activeChat = nil }
        modelContext.delete(thread)
        try? modelContext.save()
    }

    /// Resumes this author's most recent thread, or opens a new one.
    private func startConversation(with name: String, fresh: Bool) {
        let key = AuthorPersona.normalize(name)
        let authorBooks = authors.first(where: { $0.name == name })?.books ?? []

        let conversation: AuthorConversation
        if !fresh, let existing = conversations.first(where: { $0.authorNormalizedName == key }) {
            conversation = existing
        } else {
            let created = AuthorConversation(authorDisplayName: name)
            modelContext.insert(created)
            try? modelContext.save()
            conversation = created
        }

        activeChat = AuthorChatModel(
            authorName: name, books: authorBooks, conversation: conversation,
            appModel: appModel, modelContext: modelContext
        )
    }
}

/// Initials medallion standing in for an author portrait.
struct AuthorAvatar: View {
    let name: String
    var size: CGFloat = 34

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var body: some View {
        Circle()
            .fill(BrandTokens.emberGradient)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
    }
}
