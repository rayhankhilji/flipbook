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
    @Environment(\.modelContext) private var modelContext
    let session: ReadingSession
    let onClose: () -> Void

    @State private var pageFieldText = ""
    @State private var showingPageJump = false
    @State private var showingReadingOptions = false
    @State private var pinchBaseZoom: CGFloat?
    @State private var showSidebar = false
    @State private var sidebarInitialized = false
    @State private var focusMode = false
    @State private var aiController: AIChatController?
    @FocusState private var readerFocused: Bool

    private var theme: ThemeDefinition { appModel.currentTheme }

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar && !focusMode {
                ReaderSidebarView(session: session, theme: theme, aiController: aiController)
                    .transition(.move(edge: .leading))
                Divider()
            }

            readingSurface
                .scaleEffect(focusMode ? 1.015 : 1.0)
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
            ensureAIController()
            if !sidebarInitialized {
                showSidebar = appModel.settings.sidebarVisibleByDefault
                sidebarInitialized = true
            }
        }
        .onChange(of: session.book.id) { _, _ in ensureAIController() }
        .onChange(of: focusMode) { _, isFocused in
            // Focus mode is a true book-only immersive view: collapse the library
            // split-view sidebar (LibraryView listens) and take the window fullscreen.
            NotificationCenter.default.post(name: .flipbookFocusModeChanged, object: isFocused)
            setWindowFullScreen(isFocused)
        }
        .onKeyPress(.leftArrow) {
            session.jump(toPage: session.currentPageIndex - pageStep)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            session.jump(toPage: session.currentPageIndex + pageStep)
            return .handled
        }
        .onKeyPress(.space) {
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
            }
        case .scroll:
            ContinuousScrollView(session: session, theme: theme)
                .simultaneousGesture(pinchToZoom, isEnabled: appModel.settings.gesturePinchToZoom)
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

    private var pinchToZoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchBaseZoom == nil {
                    pinchBaseZoom = session.zoom
                }
                session.setZoom((pinchBaseZoom ?? 1) * value.magnification)
            }
            .onEnded { _ in
                pinchBaseZoom = nil
            }
    }

    // MARK: - Navigation & commands

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

    /// Keeps a single `AIChatController` alive for the life of the window, recreating it
    /// only when the open book changes — shared by the sidebar tab and the centered page.
    private func ensureAIController() {
        if aiController?.book.id != session.book.id {
            aiController = AIChatController(session: session, modelContext: modelContext, settings: appModel.settings)
        }
    }

    private func commitPageJump() {
        if let page = Int(pageFieldText), page >= 1, page <= session.pageCount {
            session.jump(toPage: page - 1)
        }
        showingPageJump = false
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

extension Notification.Name {
    /// Posted by the reader when focus/immersive mode toggles; carries a `Bool`.
    static let flipbookFocusModeChanged = Notification.Name("flipbookFocusModeChanged")
}
