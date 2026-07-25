import AppKit
import FlipbookCore
import FlipbookDesignSystem
import SwiftUI

/// The reading window. Toolbar is deliberately spare — four buttons and a page
/// indicator; every reading control (view mode, theme, zoom, typography, focus)
/// lives in the single "Aa" popover, Apple Books style. Zoom and mode shortcuts
/// stay global through the View menu (`ReaderMenuCommands`).
struct ReaderView: View {
    @Environment(AppModel.self) private var appModel
    let session: ReadingSession
    let onClose: () -> Void

    @State private var pageFieldText = ""
    @State private var showingPageJump = false
    @State private var showingReadingOptions = false
    @State private var bookPinchScale: CGFloat = 1
    @State private var bookPinchAnchor: UnitPoint = .center
    @State private var showSidebar = false
    @State private var sidebarInitialized = false
    @State private var focusMode = false
    @State private var showChat = false
    @State private var chat: BookChatModel?
    @FocusState private var readerFocused: Bool

    private var theme: ThemeDefinition { appModel.currentTheme }

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar && !focusMode {
                ReaderSidebarView(session: session, theme: theme)
                    .transition(.move(edge: .leading))
                Divider()
            }

            readingSurface
                .scaleEffect(focusMode ? 1.015 : 1.0)

            if showChat, !focusMode, let chat {
                Divider()
                ChatPanelView(chat: chat) {
                    withAnimation(AnimationTokens.standard) { showChat = false }
                }
                .transition(.move(edge: .trailing))
            }
        }
        .background(theme.canvasColor)
        .overlay(alignment: .top) {
            if focusMode {
                FocusEscapeBar(session: session, pageStep: pageStep) {
                    focusMode = false
                }
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if session.highlighterActive {
                HighlighterBar(session: session) {
                    withAnimation(AnimationTokens.quick) {
                        session.highlighterActive = false
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(AnimationTokens.standard, value: session.highlighterActive)
        .animation(AnimationTokens.standard, value: theme.id)
        .animation(AnimationTokens.standard, value: focusMode)
        .navigationTitle(session.book.title)
        .toolbar { toolbarContent }
        .toolbarVisibility(focusMode ? .hidden : .visible, for: .windowToolbar)
        // Arrow keys/Space only reach onKeyPress when the reader owns keyboard focus —
        // claim it on open and reclaim it on click.
        .focusable()
        .focusEffectDisabled()
        .focused($readerFocused)
        .simultaneousGesture(TapGesture().onEnded { readerFocused = true })
        .onAppear {
            readerFocused = true
            appModel.beginReading()
            if !sidebarInitialized {
                showSidebar = appModel.settings.sidebarVisibleByDefault
                sidebarInitialized = true
            }
        }
        .onDisappear {
            appModel.endReading()
        }
        .onChange(of: session.currentPageIndex) { _, _ in
            refreshChatContext()
        }
        .onChange(of: focusMode) { _, isFocused in
            // Focus mode is "nothing but the book": drop the marker bar, and make sure the
            // window is full screen even when auto-fullscreen is disabled in Settings
            // (leaving again restores the compact window in that case).
            if isFocused {
                withAnimation(AnimationTokens.quick) { session.highlighterActive = false }
                setWindowFullScreen(true)
            } else if !appModel.settings.openBookFullScreen {
                setWindowFullScreen(false)
            }
        }
        .onKeyPress(.leftArrow) {
            guard !isEditingText else { return .ignored }
            session.jump(toPage: session.currentPageIndex - pageStep)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !isEditingText else { return .ignored }
            session.jump(toPage: session.currentPageIndex + pageStep)
            return .handled
        }
        .onKeyPress(.space) {
            guard !isEditingText else { return .ignored }
            session.jump(toPage: session.currentPageIndex + pageStep)
            return .handled
        }
        .onKeyPress(.escape) {
            guard focusMode else { return .ignored }
            focusMode = false
            return .handled
        }
        .onReceive(NotificationCenter.default.publisher(for: .flipbookReaderCommand)) { notification in
            handleReaderCommand(notification)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: onClose) {
                Label("Library", systemImage: "chevron.left")
            }
            .help("Back to Library")

            Button {
                withAnimation(AnimationTokens.standard) {
                    showSidebar.toggle()
                }
            } label: {
                Label("Sidebar", systemImage: "sidebar.left")
            }
            .help(showSidebar ? "Hide Sidebar (⌥⌘S)" : "Show Sidebar (⌥⌘S)")
        }

        ToolbarItem(placement: .principal) {
            Button {
                pageFieldText = "\(session.currentPageIndex + 1)"
                showingPageJump = true
            } label: {
                Text("\(session.currentPageIndex + 1) of \(session.pageCount)")
                    .font(TypographyTokens.callout)
                    .monospacedDigit()
                    .foregroundStyle(ColorTokens.chromeSecondaryText)
            }
            .buttonStyle(.plain)
            .help("Go to Page…")
            .popover(isPresented: $showingPageJump, arrowEdge: .bottom) {
                pageJumpPopover
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: toggleChat) {
                Label("AI Assistant", systemImage: "sparkles")
                    .foregroundStyle(showChat ? Color.accentColor : Color.primary)
            }
            .help("Ask AI about this book")

            Button {
                withAnimation(AnimationTokens.quick) {
                    session.highlighterActive.toggle()
                }
            } label: {
                Label("Highlighter", systemImage: "highlighter")
                    .foregroundStyle(session.highlighterActive ? Color.accentColor : Color.primary)
            }
            .help(session.highlighterActive
                ? "Turn off highlighter"
                : "Highlighter — drag to mark, tap a mark to erase")

            Button {
                _ = session.addStickyNote(pageIndex: session.currentPageIndex)
            } label: {
                Label("Add Note", systemImage: "note.text.badge.plus")
            }
            .help("Add a sticky note to this page — drag it anywhere, click to collapse")

            Button {
                withAnimation(AnimationTokens.quick) {
                    session.toggleBookmark()
                }
            } label: {
                Label(
                    session.isCurrentPageBookmarked ? "Remove Bookmark" : "Add Bookmark",
                    systemImage: session.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark"
                )
                .foregroundStyle(
                    session.isCurrentPageBookmarked
                        ? Color(red: 0.78, green: 0.35, blue: 0.28)
                        : Color.primary
                )
            }
            .help(session.isCurrentPageBookmarked ? "Remove Bookmark (⌘D)" : "Bookmark This Page (⌘D)")

            Button {
                showingReadingOptions = true
            } label: {
                Label("Reading Options", systemImage: "textformat.size")
            }
            .help("Reading Options — view, theme, zoom, typography")
            .popover(isPresented: $showingReadingOptions, arrowEdge: .bottom) {
                ReadingOptionsPopover(session: session) {
                    showingReadingOptions = false
                    focusMode = true
                }
            }
        }
    }

    // MARK: - Reading surface

    @ViewBuilder
    private var readingSurface: some View {
        if session.reflowMode {
            ReflowView(session: session, theme: theme)
        } else {
            paginatedSurface
                .overlay(canvasVignette)
        }
    }

    /// A whisper of edge darkening pulls the eye to the page, like a reading lamp.
    private var canvasVignette: some View {
        RadialGradient(
            colors: [.clear, .clear, .black.opacity(theme.isDark ? 0.28 : 0.10)],
            center: .center,
            startRadius: 0,
            endRadius: 900
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var paginatedSurface: some View {
        switch session.navigationMode {
        case .pageTurn:
            GeometryReader { geometry in
                let spreadLayout = BookSpreadLayout.compute(
                    bounds: geometry.size,
                    spread: BookSpreadLayout.spread(containing: session.currentPageIndex),
                    pageCount: session.pageCount
                ) { session.document.pageSize(at: $0) }
                PageTurnContainerView(
                    session: session,
                    theme: theme,
                    // A trackpad swipe would flip the page out from under a marker stroke,
                    // so pause it while the highlighter is on (arrow keys still turn).
                    swipeEnabled: appModel.settings.gestureSwipeToTurnPage && !session.highlighterActive
                )
                .overlay(
                    // Bookmark ribbon + committed highlights over each resting page, and —
                    // when the highlighter is on — the marker gesture. Mouse drags don't
                    // turn pages (that's trackpad/arrows), so marking is safe here too.
                    pageTurnAnnotations(spreadLayout)
                )
                .overlay(
                    // Movable, collapsible sticky notes — drawn over the whole surface so
                    // they can sit in the margins as well as over the page.
                    StickyNotesLayer(session: session, layout: spreadLayout)
                )
            }
            // Book-mode pinch is a cursor-anchored "lean in": the spread magnifies under
            // the fingers to read small print, then springs back on release — the spread
            // itself always fits the window, so persistent zoom would strand its corners.
            .scaleEffect(bookPinchScale, anchor: bookPinchAnchor)
            .simultaneousGesture(
                bookPinch,
                isEnabled: appModel.settings.gesturePinchToZoom && !session.highlighterActive
            )
        case .scroll:
            ContinuousScrollView(
                session: session,
                theme: theme,
                magnifyEnabled: appModel.settings.gesturePinchToZoom
            )
        }
    }

    private var bookPinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                bookPinchAnchor = value.startAnchor
                bookPinchScale = min(max(value.magnification, 0.9), 2.5)
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    bookPinchScale = 1
                }
                bookPinchAnchor = .center
            }
    }

    /// Annotation overlays for a page-turn spread — one per visible page so marks can be
    /// made on the left page as well as the right.
    @ViewBuilder
    private func pageTurnAnnotations(_ layout: BookSpreadLayout) -> some View {
        ZStack {
            if !layout.isSingle, let left = layout.leftPageIndex {
                annotationOverlay(pageIndex: left, rect: layout.leftRect)
            }
            if let right = layout.rightPageIndex ?? layout.leftPageIndex {
                annotationOverlay(pageIndex: right, rect: layout.rightRect)
            }
        }
    }

    private func annotationOverlay(pageIndex: Int, rect: CGRect) -> some View {
        PageAnnotationsOverlay(
            session: session,
            pageIndex: pageIndex,
            displayedSize: rect.size,
            theme: theme
        )
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    // MARK: - Navigation & commands

    /// Whether keyboard focus is inside a text editor (sticky note, page-jump field…) —
    /// reading keys (space/arrows) must not turn pages out from under typing.
    private var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    /// Arrow keys move one page while scrolling, one spread (two pages) in book mode.
    private var pageStep: Int {
        session.navigationMode == .pageTurn && !session.reflowMode ? 2 : 1
    }

    private func handleReaderCommand(_ notification: Notification) {
        guard let command = notification.object as? ReaderCommand else { return }
        switch command {
        case .nextPage:
            session.jump(toPage: session.currentPageIndex + pageStep)
        case .previousPage:
            session.jump(toPage: session.currentPageIndex - pageStep)
        case .toggleSidebar:
            withAnimation(AnimationTokens.standard) { showSidebar.toggle() }
        case .toggleFocusMode:
            focusMode.toggle()
        case .toggleBookmark:
            withAnimation(AnimationTokens.quick) { session.toggleBookmark() }
        case .toggleNavigationMode:
            let newMode: NavigationMode = session.navigationMode == .pageTurn ? .scroll : .pageTurn
            withAnimation(AnimationTokens.standard) { session.setNavigationMode(newMode) }
        case .zoomIn:
            session.setZoom(session.zoom + 0.25)
        case .zoomOut:
            session.setZoom(session.zoom - 0.25)
        case .zoomReset:
            session.setZoom(1.0)
        case .toggleReflow:
            withAnimation(AnimationTokens.standard) { session.reflowMode.toggle() }
        }
    }

    // MARK: - Page jump

    private var pageJumpPopover: some View {
        HStack(spacing: SpacingTokens.sm) {
            Text("Page")
                .font(TypographyTokens.callout)
            TextField("Page", text: $pageFieldText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .onSubmit(commitPageJump)
            Button("Go", action: commitPageJump)
                .buttonStyle(.flipbook(prominent: true))
        }
        .padding(SpacingTokens.md)
    }

    private func commitPageJump() {
        if let page = Int(pageFieldText), page >= 1, page <= session.pageCount {
            session.jump(toPage: page - 1)
        }
        showingPageJump = false
    }

    /// Opens/closes the AI panel, creating the conversation lazily on first use.
    private func toggleChat() {
        if chat == nil {
            chat = BookChatModel(
                bookTitle: session.book.title,
                bookAuthor: session.book.authorHint,
                appModel: appModel
            )
        }
        withAnimation(AnimationTokens.standard) { showChat.toggle() }
        if showChat { refreshChatContext() }
    }

    /// Keeps the conversation's page context current so auto-context can ground answers
    /// in what the reader is actually looking at.
    private func refreshChatContext() {
        guard let chat else { return }
        let index = session.currentPageIndex
        chat.updateContext(pageNumber: index + 1, pageText: session.document.page(at: index)?.string)
    }

    /// Enters/exits native macOS full screen, matching `on` (no-op if already there).
    private func setWindowFullScreen(_ on: Bool) {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first else { return }
            let isFull = window.styleMask.contains(.fullScreen)
            if on != isFull {
                window.toggleFullScreen(nil)
            }
        }
    }
}
