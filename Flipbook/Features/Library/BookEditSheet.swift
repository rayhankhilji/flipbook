import FlipbookCore
import FlipbookDesignSystem
import SwiftUI

/// A small sheet for renaming a book and editing its author. Writes straight back to the
/// `Book` on save (SwiftData autosaves via the shared context).
struct BookEditSheet: View {
    let book: Book
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var author: String

    init(book: Book, onSave: @escaping (String, String) -> Void) {
        self.book = book
        self.onSave = onSave
        _title = State(initialValue: book.title)
        _author = State(initialValue: book.authorHint ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.lg) {
            Text("Edit Book")
                .font(TypographyTokens.headline)

            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                Text("Title").font(TypographyTokens.caption).foregroundStyle(ColorTokens.chromeSecondaryText)
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)

                Text("Author").font(TypographyTokens.caption).foregroundStyle(ColorTokens.chromeSecondaryText)
                TextField("Author", text: $author)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.flipbook(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(SpacingTokens.xl)
        .frame(width: 380)
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }
        onSave(trimmedTitle, author.trimmingCharacters(in: .whitespaces))
        dismiss()
    }
}
