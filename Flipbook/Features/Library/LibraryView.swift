import FlipbookCore
import FlipbookDesignSystem
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Which shelf the sidebar is showing. Derived from reading progress, not stored.
enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case reading
    case finished
    case unread

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Books"
        case .reading: "Reading Now"
        case .finished: "Finished"
        case .unread: "Not Started"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "books.vertical"
        case .reading: "book"
        case .finished: "checkmark.seal"
        case .unread: "book.closed"
        }
    }

    func matches(_ book: Book) -> Bool {
        let index = book.progress?.currentPageIndex ?? 0
        switch self {
        case .all: return true
        case .reading: return index > 0 && index < book.pageCount - 1
        case .finished: return book.pageCount > 0 && index >= book.pageCount - 1
        case .unread: return index == 0
        }
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case recentlyAdded
    case recentlyRead
    case title
    case author

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .recentlyRead: "Recently Read"
        case .title: "Title"
        case .author: "Author"
        }
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]

    @State private var viewModel: LibraryViewModel?
    @State private var isDropTargeted = false
    @State private var selectedBookID: UUID?
    @State private var showingRelinkPicker: Book?
    @State private var activeSession: ReadingSession?
    @State private var filter: LibraryFilter = .all
    @State private var searchText = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @AppStorage("librarySortOrder") private var sortOrder: LibrarySort = .recentlyAdded

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: SpacingTokens.lg)]

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $filter) {
                Section("Library") {
                    ForEach(LibraryFilter.allCases) { shelf in
                        Label(shelf.title, systemImage: shelf.systemImage)
                            .tag(shelf)
                            .badge(shelf == .all ? 0 : books.count(where: shelf.matches))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                if let activeSession {
                    ReaderView(session: activeSession) {
                        withAnimation(AnimationTokens.standard) {
                            self.activeSession = nil
                        }
                    }
                } else {
                    content
                        .navigationTitle(filter == .all ? "Flipbook" : filter.title)
                        .searchable(text: $searchText, placement: .toolbar, prompt: "Search title or author")
                        .toolbar { libraryToolbar }
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = LibraryViewModel(modelContext: modelContext)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .flipbookImportRequested)) { _ in
            presentOpenPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .flipbookFocusModeChanged)) { note in
            // Immersive reading collapses the shelves sidebar entirely; restore on exit.
            let focused = (note.object as? Bool) ?? false
            withAnimation(AnimationTokens.standard) {
                columnVisibility = focused ? .detailOnly : .automatic
            }
        }
        .onOpenURL { url in
            openExternalPDF(at: url)
        }
        .alert(
            "Import Failed",
            isPresented: Binding(
                get: { viewModel?.importErrorMessage != nil },
                set: { if !$0 { viewModel?.importErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel?.importErrorMessage ?? "")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Sort By", selection: $sortOrder) {
                    ForEach(LibrarySort.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort Library")

            Button {
                presentOpenPanel()
            } label: {
                Label("Import PDF", systemImage: "plus")
            }
            .help("Import PDF… (⌘O)")
        }
    }

    // MARK: - Shelf contents

    /// The visible shelf: filter → search → sort, all client-side (libraries are small).
    private var shelfBooks: [Book] {
        var result = books.filter(filter.matches)
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || ($0.authorHint?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        switch sortOrder {
        case .recentlyAdded:
            return result // @Query already sorts by dateAdded descending
        case .recentlyRead:
            return result.sorted { ($0.dateLastOpened ?? .distantPast) > ($1.dateLastOpened ?? .distantPast) }
        case .title:
            return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .author:
            return result.sorted { ($0.authorHint ?? "\u{10FFFF}").localizedStandardCompare($1.authorHint ?? "\u{10FFFF}") == .orderedAscending }
        }
    }

    @ViewBuilder
    private var content: some View {
        if books.isEmpty {
            emptyState
        } else if shelfBooks.isEmpty {
            noMatchesState
        } else {
            libraryGrid
        }
    }

    private var libraryGrid: some View {
        ScrollView {
            HStack(alignment: .firstTextBaseline) {
                Text(filter.title)
                    .font(TypographyTokens.bookTitleLarge)
                    .foregroundStyle(ColorTokens.chromeText)
                Spacer()
                Text(shelfBooks.count == 1 ? "1 book" : "\(shelfBooks.count) books")
                    .font(TypographyTokens.caption)
                    .foregroundStyle(ColorTokens.chromeSecondaryText)
            }
            .padding(.horizontal, SpacingTokens.xl)
            .padding(.top, SpacingTokens.lg)

            LazyVGrid(columns: columns, spacing: SpacingTokens.xl) {
                ForEach(shelfBooks) { book in
                    BookCardView(book: book, isSelected: selectedBookID == book.id)
                        .onTapGesture(count: 2) {
                            open(book)
                        }
                        .onTapGesture(count: 1) {
                            selectedBookID = book.id
                        }
                        .contextMenu {
                            Button("Open") { open(book) }
                            if book.isMissing {
                                Button("Locate File…") {
                                    showingRelinkPicker = book
                                }
                            }
                            Button("Remove from Library", role: .destructive) {
                                viewModel?.remove(book)
                            }
                        }
                }
            }
            .padding(SpacingTokens.xl)
            .animation(AnimationTokens.standard, value: shelfBooks.map(\.id))
        }
        .background(BrandTokens.libraryBackground(for: colorScheme))
        .background(dropOverlay)
        .fileImporter(
            isPresented: Binding(
                get: { showingRelinkPicker != nil },
                set: { if !$0 { showingRelinkPicker = nil } }
            ),
            allowedContentTypes: [.pdf]
        ) { result in
            if let book = showingRelinkPicker, case .success(let url) = result {
                viewModel?.relink(book, to: url)
            }
            showingRelinkPicker = nil
        }
    }

    private var emptyState: some View {
        VStack(spacing: SpacingTokens.lg) {
            Image(systemName: "book.pages")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(BrandTokens.emberGradient)

            VStack(spacing: SpacingTokens.sm) {
                Text("Every book begins with an open page")
                    .font(TypographyTokens.bookTitleLarge)
                    .foregroundStyle(ColorTokens.chromeText)

                Text("Drag a PDF here, or press ⌘O to open one")
                    .font(TypographyTokens.body)
                    .foregroundStyle(ColorTokens.chromeSecondaryText)
            }

            Button("Import PDF…") {
                presentOpenPanel()
            }
            .buttonStyle(.flipbook(prominent: true))
            .padding(.top, SpacingTokens.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandTokens.libraryBackground(for: colorScheme))
        .background(dropOverlay)
        .contentShape(Rectangle())
    }

    /// Books exist, but nothing on this shelf / matching the search.
    private var noMatchesState: some View {
        VStack(spacing: SpacingTokens.md) {
            Image(systemName: searchText.isEmpty ? filter.systemImage : "magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(ColorTokens.chromeSecondaryText)
            Text(searchText.isEmpty ? "Nothing on this shelf yet" : "No books match “\(searchText)”")
                .font(TypographyTokens.headline)
                .foregroundStyle(ColorTokens.chromeSecondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandTokens.libraryBackground(for: colorScheme))
        .background(dropOverlay)
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusLarge, style: .continuous)
            .strokeBorder(
                ColorTokens.accent(for: "graphite").opacity(isDropTargeted ? 0.6 : 0),
                style: StrokeStyle(lineWidth: 2, dash: [8, 6])
            )
            .padding(SpacingTokens.md)
            .allowsHitTesting(false)
            .animation(AnimationTokens.quick, value: isDropTargeted)
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onDrop(of: [.pdf], delegate: ImportDropDelegate(
                        viewModel: viewModel ?? LibraryViewModel(modelContext: modelContext),
                        isTargeted: $isDropTargeted
                    ))
            )
    }

    /// Handles PDFs opened from Finder ("Open With → Flipbook"): reuses the existing
    /// library entry if the file is already imported, otherwise imports then opens.
    private func openExternalPDF(at url: URL) {
        guard url.pathExtension.lowercased() == "pdf" else { return }
        if let existing = books.first(where: { $0.lastKnownPath == url.path }) {
            open(existing)
            return
        }
        viewModel?.importPDFs(at: [url])
        if let imported = books.first(where: { $0.lastKnownPath == url.path }) {
            open(imported)
        }
    }

    private func open(_ book: Book) {
        guard let session = ReadingSession(book: book, modelContext: modelContext) else {
            // Session init flags the book missing when the file can't be resolved.
            showingRelinkPicker = book
            return
        }
        withAnimation(AnimationTokens.standard) {
            activeSession = session
        }
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            viewModel?.importPDFs(at: panel.urls)
        }
    }
}
