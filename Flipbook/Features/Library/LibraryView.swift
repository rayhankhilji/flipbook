import FlipbookCore
import FlipbookDesignSystem
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Which shelf the sidebar is showing. Derived from reading progress, not stored.
enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case reading
    case favorites
    case finished
    case unread

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Books"
        case .reading: "Reading Now"
        case .favorites: "Favourites"
        case .finished: "Finished"
        case .unread: "Not Started"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "books.vertical"
        case .reading: "book"
        case .favorites: "heart"
        case .finished: "checkmark.seal"
        case .unread: "book.closed"
        }
    }

    func matches(_ book: Book) -> Bool {
        let index = book.progress?.currentPageIndex ?? 0
        switch self {
        case .all: return true
        case .reading: return index > 0 && index < book.pageCount - 1
        case .favorites: return book.isFavorite
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

/// Top-level sidebar destination: the dashboard, a computed shelf, or a user folder.
enum SidebarItem: Hashable {
    case home
    case authors
    case shelf(LibraryFilter)
    case folder(UUID)
}

struct LibraryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]
    @Query(sort: \Folder.sortIndex) private var folders: [Folder]

    @State private var viewModel: LibraryViewModel?
    @State private var isDropTargeted = false
    @State private var selectedBookID: UUID?
    @State private var showingRelinkPicker: Book?
    @State private var activeSession: ReadingSession?
    @State private var selection: SidebarItem? = .home
    @State private var searchText = ""
    @State private var windowManager = WindowManager()
    @AppStorage("librarySortOrder") private var sortOrder: LibrarySort = .recentlyAdded

    // Book editing / folder management
    @State private var editingBook: Book?
    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var pendingFolderBook: Book?
    @State private var renamingFolder: Folder?
    @State private var folderNameDraft = ""

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: SpacingTokens.lg)]

    var body: some View {
        // A hand-rolled split view: the system NavigationSplitView draws its own materials,
        // insets, and rounded borders that fight the cream/mocha skin — this keeps every
        // surface and hairline ours.
        HStack(spacing: 0) {
            if activeSession == nil {
                sidebar
                    .frame(width: 224)
                Rectangle()
                    .fill(ColorTokens.creamHairline.opacity(0.35))
                    .frame(width: 1)
                    .ignoresSafeArea()
            }
            detail
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        // Compact and non-resizable while browsing (fixed frame + scene .contentSize
        // resizability); flexible while reading so full screen can fill the display.
        .frame(
            width: activeSession == nil ? WindowManager.librarySize.width : nil,
            height: activeSession == nil ? WindowManager.librarySize.height : nil
        )
        .frame(
            minWidth: activeSession == nil ? nil : 640,
            maxWidth: activeSession == nil ? nil : .infinity,
            minHeight: activeSession == nil ? nil : 480,
            maxHeight: activeSession == nil ? nil : .infinity
        )
        .background(WindowAccessor { windowManager.attach($0) })
        .onAppear {
            if viewModel == nil {
                viewModel = LibraryViewModel(modelContext: modelContext)
            }
            // Leaving full screen (green traffic-light button) drops the open book and
            // returns to the compact library window — but only in auto-fullscreen mode.
            // When the user reads windowed (Settings), fullscreen is just focus mode's
            // temporary state and exiting it must not close their book.
            windowManager.onExitFullScreen = {
                if appModel.settings.openBookFullScreen, activeSession != nil {
                    withAnimation(AnimationTokens.standard) { activeSession = nil }
                }
            }
        }
        // Opening a book takes the window full screen (unless disabled in Settings);
        // closing it snaps back to the compact, side-by-side library layout.
        .onChange(of: activeSession == nil) { _, isLibrary in
            if isLibrary {
                windowManager.exitReading()
            } else if appModel.settings.openBookFullScreen {
                windowManager.enterReading()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .flipbookImportRequested)) { _ in
            presentOpenPanel()
        }
        .onOpenURL { url in
            openExternalPDF(at: url)
        }
        .sheet(item: $editingBook) { book in
            BookEditSheet(book: book) { title, author in
                viewModel?.rename(book, title: title, author: author)
            }
        }
        .alert("New Folder", isPresented: $showingNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) { pendingFolderBook = nil; newFolderName = "" }
            Button("Create") { commitNewFolder() }
        } message: {
            Text("Group books together into a collection.")
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )) {
            TextField("Folder name", text: $folderNameDraft)
            Button("Cancel", role: .cancel) { renamingFolder = nil }
            Button("Save") {
                if let folder = renamingFolder {
                    let trimmed = folderNameDraft.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { viewModel?.renameFolder(folder, to: trimmed) }
                }
                renamingFolder = nil
            }
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

    // MARK: - Sidebar

    /// A fully hand-rolled sidebar: plain buttons with a drawn selected pill, our own section
    /// headers, and a bubbly pill footer — no system List/split-view materials or borders to
    /// clash with the cream/mocha skin.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sidebarRow(.home, title: "Home", symbol: "house")
                    sidebarRow(.authors, title: "Authors", symbol: "person.and.background.dotted")

                    sectionHeader("Library")
                    ForEach(LibraryFilter.allCases) { shelf in
                        sidebarRow(
                            .shelf(shelf),
                            title: shelf.title,
                            symbol: shelf.systemImage,
                            badge: shelf == .all ? nil : books.count(where: shelf.matches)
                        )
                    }

                    HStack {
                        sectionHeader("Folders")
                        Spacer()
                        Button {
                            pendingFolderBook = nil
                            newFolderName = ""
                            showingNewFolder = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(ColorTokens.inkSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("New Folder")
                        .padding(.trailing, SpacingTokens.sm)
                        .padding(.top, SpacingTokens.md)
                    }

                    if folders.isEmpty {
                        Text("No folders yet")
                            .font(TypographyTokens.caption)
                            .foregroundStyle(ColorTokens.inkSecondary.opacity(0.7))
                            .padding(.horizontal, SpacingTokens.sm + SpacingTokens.sm)
                            .padding(.vertical, SpacingTokens.xs)
                    }
                    ForEach(folders) { folder in
                        sidebarRow(
                            .folder(folder.id),
                            title: folder.name,
                            symbol: folder.symbol,
                            badge: folder.books.count
                        )
                        .contextMenu {
                            Button("Rename…") {
                                folderNameDraft = folder.name
                                renamingFolder = folder
                            }
                            Button("Delete Folder", role: .destructive) {
                                if selection == .folder(folder.id) { selection = .home }
                                viewModel?.deleteFolder(folder)
                            }
                        }
                    }
                }
                .padding(.horizontal, SpacingTokens.sm)
                .padding(.top, SpacingTokens.sm)
            }

            Spacer(minLength: 0)
            sidebarFooter
        }
        .background(ColorTokens.sidebarSurface.ignoresSafeArea())
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(TypographyTokens.caption.weight(.semibold))
            .foregroundStyle(ColorTokens.inkSecondary.opacity(0.8))
            .textCase(.uppercase)
            .kerning(0.6)
            .padding(.horizontal, SpacingTokens.sm + SpacingTokens.sm)
            .padding(.top, SpacingTokens.md)
            .padding(.bottom, SpacingTokens.xs)
    }

    private func sidebarRow(_ item: SidebarItem, title: String, symbol: String, badge: Int? = nil) -> some View {
        let isSelected = selection == item
        return Button {
            selection = item
        } label: {
            HStack(spacing: SpacingTokens.sm) {
                Image(systemName: symbol)
                    .frame(width: 18)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(TypographyTokens.caption)
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : ColorTokens.inkSecondary)
                }
            }
            .font(TypographyTokens.callout)
            .foregroundStyle(isSelected ? .white : ColorTokens.ink)
            .padding(.horizontal, SpacingTokens.sm)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusSmall, style: .continuous)
                    .fill(isSelected ? Color.accentColor : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Bubbly pill footer — Settings and Import as rounded chips that match the bento cards.
    private var sidebarFooter: some View {
        HStack(spacing: SpacingTokens.sm) {
            SettingsLink {
                footerPillLabel("Settings", symbol: "gearshape.fill")
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")

            Button {
                presentOpenPanel()
            } label: {
                footerPillLabel("Import", symbol: "plus")
            }
            .buttonStyle(.plain)
            .help("Import PDF… (⌘O)")
        }
        .padding(SpacingTokens.sm)
    }

    private func footerPillLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(TypographyTokens.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(ColorTokens.ink.opacity(0.9))
        .padding(.horizontal, SpacingTokens.md)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Capsule(style: .continuous).fill(ColorTokens.sidebarFooter))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(ColorTokens.creamHairline.opacity(0.3), lineWidth: 0.5)
        )
        .contentShape(Capsule(style: .continuous))
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let activeSession {
            ReaderView(session: activeSession) {
                withAnimation(AnimationTokens.standard) {
                    self.activeSession = nil
                }
            }
        } else if selection == .home {
            DashboardView(books: books, openBook: open)
                .navigationTitle("Home")
                .toolbar { libraryToolbar }
        } else if selection == .authors {
            AuthorsView(books: books)
                .navigationTitle("Authors")
        } else {
            content
                .navigationTitle(currentTitle)
                .toolbar { libraryToolbar }
        }
    }

    private var currentTitle: String {
        switch selection {
        case .home, .none: return "Home"
        case .authors: return "Authors"
        case .shelf(let f): return f.title
        case .folder(let id): return folders.first(where: { $0.id == id })?.name ?? "Folder"
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

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Settings (⌘,)")

            Button {
                presentOpenPanel()
            } label: {
                Label("Import PDF", systemImage: "plus")
            }
            .help("Import PDF… (⌘O)")
        }
    }

    // MARK: - Shelf contents

    /// The books for the current selection (shelf or folder), before search/sort.
    private var baseBooks: [Book] {
        switch selection {
        case .shelf(let f):
            return books.filter(f.matches)
        case .folder(let id):
            guard let folder = folders.first(where: { $0.id == id }) else { return [] }
            let ids = Set(folder.books.map(\.id))
            return books.filter { ids.contains($0.id) }
        default:
            return books
        }
    }

    /// baseBooks → search → sort, pinned books floated to the front.
    private var shelfBooks: [Book] {
        var result = baseBooks
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || ($0.authorHint?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        switch sortOrder {
        case .recentlyAdded:
            break // @Query already sorts by dateAdded descending
        case .recentlyRead:
            result.sort { ($0.dateLastOpened ?? .distantPast) > ($1.dateLastOpened ?? .distantPast) }
        case .title:
            result.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .author:
            result.sort { ($0.authorHint ?? "\u{10FFFF}").localizedStandardCompare($1.authorHint ?? "\u{10FFFF}") == .orderedAscending }
        }
        // Pinned books always lead, keeping their relative order within each group.
        return result.filter(\.isPinned) + result.filter { !$0.isPinned }
    }

    @ViewBuilder
    private var content: some View {
        if books.isEmpty {
            emptyState
        } else {
            dashboardGrid
        }
    }

    private var dashboardGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.lg) {
                HStack(alignment: .center, spacing: SpacingTokens.sm) {
                    Text(currentTitle)
                        .font(TypographyTokens.bookTitleLarge)
                        .foregroundStyle(ColorTokens.ink)
                    Text(shelfBooks.count == 1 ? "1 book" : "\(shelfBooks.count) books")
                        .font(TypographyTokens.caption.weight(.semibold))
                        .foregroundStyle(ColorTokens.inkSecondary)
                        .padding(.horizontal, SpacingTokens.sm)
                        .padding(.vertical, 4)
                        .background(Capsule(style: .continuous).fill(BrandTokens.tileToast))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(ColorTokens.creamHairline.opacity(0.3), lineWidth: 0.5)
                        )
                    Spacer()
                }

                searchBar

                if shelfBooks.isEmpty {
                    noMatchesInline
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    LazyVGrid(columns: columns, spacing: SpacingTokens.xl) {
                        ForEach(shelfBooks) { book in
                            BookCardView(book: book, isSelected: selectedBookID == book.id) {
                                editingBook = book
                            }
                            .onTapGesture(count: 2) { open(book) }
                            .onTapGesture(count: 1) { selectedBookID = book.id }
                            .contextMenu { bookContextMenu(book) }
                        }
                    }
                    .animation(AnimationTokens.standard, value: shelfBooks.map(\.id))
                }
            }
            .padding(SpacingTokens.xl)
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

    @ViewBuilder
    private func bookContextMenu(_ book: Book) -> some View {
        Button("Open") { open(book) }
        Button("Edit Title & Author…", systemImage: "pencil") { editingBook = book }
        Divider()
        Button(
            book.isFavorite ? "Remove from Favourites" : "Add to Favourites",
            systemImage: book.isFavorite ? "heart.slash" : "heart"
        ) { viewModel?.toggleFavorite(book) }
        Button(
            book.isPinned ? "Unpin" : "Pin to Top",
            systemImage: book.isPinned ? "pin.slash" : "pin"
        ) { viewModel?.togglePin(book) }
        Menu {
            if folders.isEmpty {
                Text("No folders yet")
            } else {
                ForEach(folders) { folder in
                    let isMember = folder.books.contains { $0.id == book.id }
                    Button {
                        viewModel?.setMembership(book, in: folder, member: !isMember)
                    } label: {
                        Label(folder.name, systemImage: isMember ? "checkmark" : folder.symbol)
                    }
                }
            }
            Divider()
            Button("New Folder…") {
                pendingFolderBook = book
                newFolderName = ""
                showingNewFolder = true
            }
        } label: {
            Label("Add to Folder", systemImage: "folder.badge.plus")
        }
        if book.isMissing {
            Button("Locate File…") { showingRelinkPicker = book }
        }
        Divider()
        Button("Remove from Library", role: .destructive) { viewModel?.remove(book) }
    }

    /// Prominent, always-visible search field on the dashboard — cream-styled, not the
    /// hidden toolbar search. Filters the current shelf by title or author.
    private var searchBar: some View {
        HStack(spacing: SpacingTokens.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ColorTokens.inkSecondary)
            TextField("Search your books by title or author", text: $searchText)
                .textFieldStyle(.plain)
                .font(TypographyTokens.body)
                .foregroundStyle(ColorTokens.ink)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(ColorTokens.inkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, SpacingTokens.md)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(BrandTokens.tileCream)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(ColorTokens.creamHairline.opacity(0.35), lineWidth: 0.5)
        )
        .frame(maxWidth: 460, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: SpacingTokens.lg) {
            Image(systemName: "book.pages")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(BrandTokens.emberGradient)

            VStack(spacing: SpacingTokens.sm) {
                Text("Every book begins with an open page")
                    .font(TypographyTokens.bookTitleLarge)
                    .foregroundStyle(ColorTokens.ink)

                Text("Drag a PDF here, or press ⌘O to open one")
                    .font(TypographyTokens.body)
                    .foregroundStyle(ColorTokens.inkSecondary)
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
    private var noMatchesInline: some View {
        VStack(spacing: SpacingTokens.md) {
            Image(systemName: searchText.isEmpty ? emptyShelfSymbol : "magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(ColorTokens.inkSecondary)
            Text(searchText.isEmpty ? "Nothing here yet" : "No books match “\(searchText)”")
                .font(TypographyTokens.headline)
                .foregroundStyle(ColorTokens.inkSecondary)
        }
    }

    private var emptyShelfSymbol: String {
        if case .shelf(let f) = selection { return f.systemImage }
        if case .folder = selection { return "folder" }
        return "books.vertical"
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: SpacingTokens.cornerRadiusLarge, style: .continuous)
            .strokeBorder(
                ColorTokens.brandPrimary.opacity(isDropTargeted ? 0.6 : 0),
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

    // MARK: - Actions

    private func commitNewFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        newFolderName = ""
        guard !name.isEmpty, let vm = viewModel else { pendingFolderBook = nil; return }
        let folder = vm.createFolder(name: name)
        if let book = pendingFolderBook {
            vm.setMembership(book, in: folder, member: true)
        }
        pendingFolderBook = nil
    }

    /// Handles PDFs opened from Finder ("Open With → Flipbook").
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
