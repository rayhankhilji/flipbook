import FlipbookCore
import FlipbookDesignSystem
import SwiftUI

/// The reader's collapsible side panel: Contents / Thumbnails / Bookmarks / Highlights.
struct ReaderSidebarView: View {
    let session: ReadingSession
    let theme: ThemeDefinition

    @Environment(AppModel.self) private var appModel

    enum Tab: String, CaseIterable, Identifiable {
        case contents, thumbnails, bookmarks, highlights
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .contents: "list.bullet.indent"
            case .thumbnails: "square.grid.2x2"
            case .bookmarks: "bookmark"
            case .highlights: "highlighter"
            }
        }

        var label: String {
            switch self {
            case .contents: "Contents"
            case .thumbnails: "Thumbnails"
            case .bookmarks: "Bookmarks"
            case .highlights: "Highlights"
            }
        }
    }

    @State private var tab: Tab = .contents

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar Section", selection: $tab) {
                ForEach(Tab.allCases) { candidate in
                    Image(systemName: candidate.symbol)
                        .tag(candidate)
                        .accessibilityLabel(Text(candidate.label))
                        .help(candidate.label)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(SpacingTokens.md)

            Divider()

            switch tab {
            case .contents:
                OutlineTabView(session: session)
            case .thumbnails:
                ThumbnailsTabView(session: session, theme: theme)
            case .bookmarks:
                BookmarksTabView(session: session)
            case .highlights:
                HighlightsTabView(session: session)
            }
        }
        .frame(width: 288)
        .animation(AnimationTokens.standard, value: tab)
        .background(.regularMaterial)
    }
}

// MARK: - Contents

private struct OutlineTabView: View {
    let session: ReadingSession

    var body: some View {
        if session.document.outline.isEmpty {
            SidebarEmptyState(
                symbol: "list.bullet.indent",
                message: "This book has no table of contents."
            )
        } else {
            outlineList
        }
    }

    private var outlineList: some View {
        VStack(spacing: 0) {
            List(session.document.outline, children: \.listChildren) { node in
                Button {
                    if let page = node.pageIndex {
                        session.jump(toPage: page)
                    }
                } label: {
                    HStack {
                        Text(node.title)
                            .font(TypographyTokens.callout)
                            .lineLimit(2)
                        Spacer()
                        if let page = node.pageIndex {
                            Text("\(page + 1)")
                                .font(TypographyTokens.caption)
                                .monospacedDigit()
                                .foregroundStyle(ColorTokens.chromeSecondaryText)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }
}

private extension OutlineNode {
    var listChildren: [OutlineNode]? {
        children.isEmpty ? nil : children
    }
}

// MARK: - Thumbnails

private struct ThumbnailsTabView: View {
    let session: ReadingSession
    let theme: ThemeDefinition

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: SpacingTokens.md)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: SpacingTokens.md) {
                    ForEach(0..<session.pageCount, id: \.self) { index in
                        ThumbnailCell(
                            session: session,
                            pageIndex: index,
                            theme: theme,
                            isCurrent: index == session.currentPageIndex
                        )
                        .id(index)
                        .onTapGesture {
                            session.jump(toPage: index)
                        }
                    }
                }
                .padding(SpacingTokens.md)
            }
            .onAppear {
                proxy.scrollTo(session.currentPageIndex, anchor: .center)
            }
        }
    }
}

private struct ThumbnailCell: View {
    let session: ReadingSession
    let pageIndex: Int
    let theme: ThemeDefinition
    let isCurrent: Bool

    @State private var image: CGImage?

    var body: some View {
        VStack(spacing: SpacingTokens.xs) {
            Group {
                if let image {
                    Image(decorative: image, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(theme.pageColor)
                        .aspectRatio(aspectRatio, contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        isCurrent ? Color.accentColor : ColorTokens.chromeSeparator.opacity(0.6),
                        lineWidth: isCurrent ? 2 : 0.5
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)

            Text("\(pageIndex + 1)")
                .font(TypographyTokens.caption)
                .monospacedDigit()
                .foregroundStyle(isCurrent ? Color.accentColor : ColorTokens.chromeSecondaryText)
        }
        .task(id: "\(pageIndex)-\(theme.id)") {
            let size = session.document.pageSize(at: pageIndex)
            let zoom = size.width > 0 ? 96 / size.width : 0.15
            image = await session.renderer.image(
                pageIndex: pageIndex,
                zoom: zoom,
                themeID: theme.id,
                screenScale: session.screenScale
            )
        }
        .accessibilityLabel(Text("Page \(pageIndex + 1)"))
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    private var aspectRatio: CGFloat {
        let size = session.document.pageSize(at: pageIndex)
        return size.height > 0 ? size.width / size.height : 0.72
    }
}

// MARK: - Bookmarks

private struct BookmarksTabView: View {
    let session: ReadingSession

    @State private var renaming: Bookmark?
    @State private var labelDraft = ""

    private var sortedBookmarks: [Bookmark] {
        session.book.bookmarks.sorted { $0.pageIndex < $1.pageIndex }
    }

    private func color(for bookmark: Bookmark) -> Color {
        HighlightPalette.color(for: bookmark.colorTag ?? "honey")
    }

    var body: some View {
        Group {
            if sortedBookmarks.isEmpty {
                SidebarEmptyState(
                    symbol: "bookmark",
                    message: "No bookmarks yet. Press ⌘D while reading to add one, then name it here to find your way back."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: SpacingTokens.sm) {
                        ForEach(sortedBookmarks, id: \.id) { bookmark in
                            bookmarkCard(bookmark)
                        }
                    }
                    .padding(SpacingTokens.md)
                }
            }
        }
        .alert("Name Bookmark", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("e.g. Key argument", text: $labelDraft)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let bookmark = renaming {
                    session.renameBookmark(bookmark, label: labelDraft)
                }
                renaming = nil
            }
        }
    }

    private func bookmarkCard(_ bookmark: Bookmark) -> some View {
        Button {
            session.jump(toPage: bookmark.pageIndex)
        } label: {
            HStack(spacing: SpacingTokens.sm) {
                Image(systemName: "bookmark.fill")
                    .font(.callout)
                    .foregroundStyle(color(for: bookmark))
                VStack(alignment: .leading, spacing: 2) {
                    Text(bookmark.label ?? "Page \(bookmark.pageIndex + 1)")
                        .font(TypographyTokens.callout)
                        .foregroundStyle(ColorTokens.chromeText)
                        .lineLimit(1)
                    Text("Page \(bookmark.pageIndex + 1)")
                        .font(TypographyTokens.caption)
                        .foregroundStyle(ColorTokens.chromeSecondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(SpacingTokens.sm)
            .background(
                RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusMedium, style: .continuous)
                    .fill(.background.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusMedium, style: .continuous)
                    .strokeBorder(ColorTokens.chromeSeparator.opacity(0.5), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename…", systemImage: "pencil") {
                labelDraft = bookmark.label ?? ""
                renaming = bookmark
            }
            Menu {
                ForEach(HighlightPalette.all) { entry in
                    Button {
                        session.setBookmarkColor(bookmark, colorTag: entry.id)
                    } label: {
                        Label(entry.name, systemImage: (bookmark.colorTag ?? "honey") == entry.id ? "checkmark" : "circle.fill")
                    }
                }
            } label: {
                Label("Colour", systemImage: "paintpalette")
            }
            Divider()
            Button("Remove Bookmark", role: .destructive) {
                withAnimation(AnimationTokens.quick) {
                    session.removeBookmark(bookmark)
                }
            }
        }
    }
}

// MARK: - Highlights

private struct HighlightsTabView: View {
    let session: ReadingSession

    @State private var expandedID: UUID?

    private var sortedHighlights: [Highlight] {
        session.book.highlights.sorted {
            ($0.pageIndex, $0.dateCreated) < ($1.pageIndex, $1.dateCreated)
        }
    }

    var body: some View {
        if sortedHighlights.isEmpty {
            SidebarEmptyState(
                symbol: "highlighter",
                message: "No highlights yet. Tap the highlighter in the toolbar, then draw across the page like a pen. Tap a mark to erase. Add notes to your marks here."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: SpacingTokens.sm) {
                    ForEach(sortedHighlights, id: \.id) { highlight in
                        HighlightNoteCard(
                            session: session,
                            highlight: highlight,
                            isExpanded: expandedID == highlight.id
                        ) {
                            withAnimation(AnimationTokens.standard) {
                                expandedID = expandedID == highlight.id ? nil : highlight.id
                            }
                        }
                    }
                }
                .padding(SpacingTokens.md)
            }
        }
    }
}

/// One annotation as a soft card: color bar, snippet, and page number in the header;
/// tapping the chevron unfolds a note editor that saves as you go.
private struct HighlightNoteCard: View {
    let session: ReadingSession
    let highlight: Highlight
    let isExpanded: Bool
    let toggleExpanded: () -> Void

    @State private var noteDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                editor
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusMedium, style: .continuous)
                .fill(.background.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusMedium, style: .continuous)
                .strokeBorder(ColorTokens.chromeSeparator.opacity(0.5), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusMedium, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: SpacingTokens.sm) {
            RoundedRectangle(cornerRadius: 2)
                .fill(HighlightPalette.color(for: highlight.colorTag))
                .frame(width: 4)

            Button {
                session.jump(toPage: highlight.pageIndex)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(snippet)
                        .font(TypographyTokens.callout)
                        .foregroundStyle(ColorTokens.chromeText)
                        .lineLimit(isExpanded ? nil : 2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: SpacingTokens.xs) {
                        Image(systemName: highlight.styleTag == "underline" ? "pencil.tip" : "highlighter")
                            .font(.system(size: 9))
                        Text("Page \(highlight.pageIndex + 1)")
                        if highlight.note?.isEmpty == false && !isExpanded {
                            Image(systemName: "note.text")
                                .font(.system(size: 9))
                        }
                    }
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.chromeSecondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button(action: toggleExpanded) {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ColorTokens.chromeSecondaryText)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isExpanded ? "Collapse note" : "Expand note"))
        }
        .padding(SpacingTokens.sm)
        .contextMenu {
            Button("Remove", role: .destructive) {
                withAnimation(AnimationTokens.quick) {
                    session.removeHighlight(highlight)
                }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.sm) {
            Divider()

            TextEditor(text: $noteDraft)
                .font(TypographyTokens.callout)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 64, maxHeight: 140)
                .overlay(alignment: .topLeading) {
                    if noteDraft.isEmpty {
                        Text("Add a note…")
                            .font(TypographyTokens.callout)
                            .foregroundStyle(ColorTokens.chromeSecondaryText.opacity(0.7))
                            .padding(.top, 1)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .onAppear {
                    noteDraft = highlight.note ?? ""
                }
                .onChange(of: noteDraft) { _, newValue in
                    session.updateNote(for: highlight, note: newValue)
                }

            HStack {
                Spacer()
                Button(role: .destructive) {
                    withAnimation(AnimationTokens.quick) {
                        session.removeHighlight(highlight)
                    }
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(TypographyTokens.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.85))
            }
        }
        .padding(.horizontal, SpacingTokens.sm)
        .padding(.bottom, SpacingTokens.sm)
    }

    private var snippet: String {
        if let text = highlight.selectedText, !text.isEmpty {
            return "“\(text.trimmingCharacters(in: .whitespacesAndNewlines))”"
        }
        return "Region on page \(highlight.pageIndex + 1)"
    }
}

// MARK: - Shared empty state

private struct SidebarEmptyState: View {
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: SpacingTokens.md) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(ColorTokens.chromeSecondaryText.opacity(0.7))
            Text(message)
                .font(TypographyTokens.caption)
                .foregroundStyle(ColorTokens.chromeSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SpacingTokens.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
