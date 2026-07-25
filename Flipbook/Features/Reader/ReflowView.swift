import FlipbookCore
import FlipbookDesignSystem
import SwiftUI

/// Reflow reading surface: the book's text re-typeset natively with the user's chosen
/// font, size, and the active theme's paper/ink colors — like a well-set printed page,
/// fully programmatic. Page origins are kept as subtle markers so progress and sidebar
/// navigation still work.
struct ReflowView: View {
    @Environment(AppModel.self) private var appModel
    let session: ReadingSession
    let theme: ThemeDefinition

    @State private var visibleBlockID: Int?
    @State private var pinchScale: CGFloat = 1
    @State private var pinchAnchor: UnitPoint = .center

    private var settings: AppSettings { appModel.settings }

    var body: some View {
        Group {
            if let blocks = session.reflowBlocks {
                content(blocks: blocks)
            } else {
                ProgressView("Preparing text…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        await session.loadReflowContentIfNeeded()
                    }
            }
        }
        .background(theme.pageColor)
        // Reflow's magnifier: pinch previews at the cursor, then commits as a *text size*
        // change — reflowed text re-sets crisply instead of scaling pixels.
        .scaleEffect(pinchScale, anchor: pinchAnchor)
        .simultaneousGesture(pinchToResizeText, isEnabled: settings.gesturePinchToZoom)
    }

    private var pinchToResizeText: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                pinchAnchor = value.startAnchor
                pinchScale = min(max(value.magnification, 0.7), 1.6)
            }
            .onEnded { value in
                let dampened = 1 + (value.magnification - 1) * 0.7
                settings.reflowTextSize = min(max(settings.reflowTextSize * dampened, 13), 32)
                appModel.save()
                pinchScale = 1
                pinchAnchor = .center
            }
    }

    private func content(blocks: [ReflowBlock]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: paragraphSpacing) {
                    ForEach(blocks) { block in
                        blockView(block)
                            .id(block.id)
                    }
                }
                .frame(maxWidth: measureWidth)
                .padding(.horizontal, SpacingTokens.xl)
                .padding(.vertical, SpacingTokens.xxl)
                .frame(maxWidth: .infinity)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $visibleBlockID, anchor: .top)
            .onChange(of: visibleBlockID) { _, newValue in
                if let newValue, let page = nearestPage(atOrBefore: newValue, in: blocks) {
                    session.setCurrentPage(page)
                }
            }
            .onChange(of: session.scrollToRequest) { _, request in
                guard let request else { return }
                if let block = blocks.first(where: { $0.kind == .pageBreak(request.pageIndex) }) {
                    withAnimation(AnimationTokens.standard) {
                        proxy.scrollTo(block.id, anchor: .top)
                    }
                }
                session.scrollToRequest = nil
            }
            .onAppear {
                if let block = blocks.first(where: { $0.kind == .pageBreak(session.currentPageIndex) }) {
                    proxy.scrollTo(block.id, anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: ReflowBlock) -> some View {
        switch block.kind {
        case .paragraph(let text):
            Text(text)
                .font(bodyFont)
                .foregroundStyle(theme.chromeTextColor)
                .lineSpacing(settings.reflowTextSize * 0.45)
                .textSelection(.enabled)

        case .pageBreak(let pageIndex):
            let notes = session.stickyNotes(forPage: pageIndex)
            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                if pageIndex > 0 {
                    HStack(spacing: SpacingTokens.md) {
                        Rectangle()
                            .fill(theme.chromeTextColor.opacity(0.15))
                            .frame(height: 0.5)
                        Text("\(pageIndex + 1)")
                            .font(TypographyTokens.caption)
                            .monospacedDigit()
                            .foregroundStyle(theme.chromeTextColor.opacity(0.4))
                        Rectangle()
                            .fill(theme.chromeTextColor.opacity(0.15))
                            .frame(height: 0.5)
                    }
                    .padding(.vertical, SpacingTokens.md)
                    .accessibilityLabel(Text("Page \(pageIndex + 1)"))
                }
                // The page's sticky notes, re-homed as chips since reflow has no page geometry.
                if !notes.isEmpty {
                    HStack(spacing: SpacingTokens.sm) {
                        ForEach(notes) { note in
                            ReflowNoteChip(session: session, note: note)
                        }
                    }
                    .padding(.bottom, SpacingTokens.xs)
                }
            }
        }
    }

    // MARK: - Typography

    private var bodyFont: Font {
        let size = settings.reflowTextSize
        switch settings.reflowFontID {
        case "sans": return .system(size: size, design: .default)
        case "rounded": return .system(size: size, design: .rounded)
        case "mono": return .system(size: size * 0.92, design: .monospaced)
        default: return .system(size: size, design: .serif)
        }
    }

    /// Comfortable measure: roughly 66 characters at the current size.
    private var measureWidth: CGFloat {
        settings.reflowTextSize * 34
    }

    private var paragraphSpacing: CGFloat {
        settings.reflowTextSize * 0.9
    }

    private func nearestPage(atOrBefore blockID: Int, in blocks: [ReflowBlock]) -> Int? {
        var page: Int?
        for block in blocks {
            if block.id > blockID { break }
            if case .pageBreak(let index) = block.kind {
                page = index
            }
        }
        return page
    }
}
