import FlipbookCore
import FlipbookDesignSystem
import SwiftUI

/// Sits over a displayed page: renders committed highlights and the bookmark ribbon,
/// and (where enabled) hosts the highlight-creation gesture — press-and-hold, then drag.
/// Text-based pages get live text selection via the PDF's text layer; scanned pages fall
/// back to drawing a region rectangle. Both render identically once committed.
struct PageAnnotationsOverlay: View {
    let session: ReadingSession
    let pageIndex: Int
    let displayedSize: CGSize
    let theme: ThemeDefinition
    let allowCreation: Bool

    @State private var liveViewRects: [CGRect] = []
    @State private var pendingPageRects: [CGRect]?
    @State private var pendingText: String?
    @State private var pendingKind: HighlightKind = .region
    @State private var pendingStyle = "highlight"
    @State private var pickerAnchor: CGPoint?

    private var pageSize: CGSize { session.document.pageSize(at: pageIndex) }
    private var scale: CGFloat { pageSize.width > 0 ? displayedSize.width / pageSize.width : 1 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            committedHighlights

            ForEach(Array(liveViewRects.enumerated()), id: \.offset) { _, rect in
                selectionRect(rect, colorID: "honey")
            }

            if session.bookmark(forPage: pageIndex) != nil {
                BookmarkRibbon()
                    .padding(.trailing, SpacingTokens.lg)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if pendingPageRects != nil, let anchor = pickerAnchor {
                colorPicker
                    .position(clampedPickerPosition(anchor))
            }
        }
        .frame(width: displayedSize.width, height: displayedSize.height, alignment: .topTrailing)
        .contentShape(Rectangle())
        .gesture(highlightGesture, isEnabled: allowCreation)
        .animation(AnimationTokens.quick, value: session.bookmark(forPage: pageIndex) != nil)
    }

    // MARK: - Committed highlights

    private var committedHighlights: some View {
        ForEach(session.highlights(forPage: pageIndex)) { highlight in
            ForEach(Array(QuadPoints.decode(highlight.quadPointsData).enumerated()), id: \.offset) { _, pageRect in
                selectionRect(
                    viewRect(fromPageRect: pageRect),
                    colorID: highlight.colorTag,
                    style: highlight.styleTag
                )
            }
        }
    }

    @ViewBuilder
    private func selectionRect(_ rect: CGRect, colorID: String, style: String = "highlight") -> some View {
        if style == "underline" {
            let barHeight = max(2.5, rect.height * 0.09)
            RoundedRectangle(cornerRadius: barHeight / 2, style: .continuous)
                .fill(HighlightPalette.color(for: colorID).opacity(0.9))
                .frame(width: rect.width, height: barHeight)
                .position(x: rect.midX, y: rect.maxY - barHeight / 2)
                .allowsHitTesting(false)
        } else {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(HighlightPalette.overlayColor(for: colorID, isDarkTheme: theme.isDark))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .blendMode(theme.isDark ? .screen : .multiply)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Creation gesture

    private var highlightGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                updateLiveSelection(from: drag.startLocation, to: drag.location)
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value else { return }
                commitLiveSelection(from: drag.startLocation, to: drag.location)
            }
    }

    private func updateLiveSelection(from start: CGPoint, to current: CGPoint) {
        if session.document.pageHasText(at: pageIndex) {
            let selection = session.document.textSelection(
                pageIndex: pageIndex,
                from: pagePoint(fromViewPoint: start),
                to: pagePoint(fromViewPoint: current)
            )
            liveViewRects = (selection?.rects ?? []).map(viewRect(fromPageRect:))
        } else {
            liveViewRects = [CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )]
        }
    }

    private func commitLiveSelection(from start: CGPoint, to end: CGPoint) {
        defer { liveViewRects = [] }

        if session.document.pageHasText(at: pageIndex) {
            guard let selection = session.document.textSelection(
                pageIndex: pageIndex,
                from: pagePoint(fromViewPoint: start),
                to: pagePoint(fromViewPoint: end)
            ), !selection.rects.isEmpty else { return }
            pendingPageRects = selection.rects
            pendingText = selection.text
            pendingKind = .textSelection
        } else {
            let viewRect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            guard viewRect.width > 8, viewRect.height > 8 else { return }
            pendingPageRects = [pageRect(fromViewRect: viewRect)]
            pendingText = nil
            pendingKind = .region
        }
        pickerAnchor = end
    }

    // MARK: - Color picker

    private var colorPicker: some View {
        HStack(spacing: SpacingTokens.sm) {
            // Style toggle: filled highlight vs. underline.
            ForEach(["highlight", "underline"], id: \.self) { style in
                Button {
                    pendingStyle = style
                } label: {
                    Image(systemName: style == "highlight" ? "highlighter" : "underline")
                        .font(.caption.weight(.semibold))
                        .frame(width: 24, height: 24)
                        .background(
                            Circle().fill(pendingStyle == style ? Color.primary.opacity(0.12) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(style == "highlight" ? "Highlight style" : "Underline style"))
                .accessibilityAddTraits(pendingStyle == style ? [.isButton, .isSelected] : .isButton)
            }

            Divider().frame(height: 16)

            ForEach(HighlightPalette.all) { entry in
                Button {
                    commitHighlight(colorTag: entry.id)
                } label: {
                    Circle()
                        .fill(entry.color)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(pendingStyle == "underline" ? "Underline" : "Highlight") in \(entry.name)"))
            }

            Divider().frame(height: 16)

            Button {
                dismissPicker()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ColorTokens.chromeSecondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Cancel highlight"))
        }
        .padding(.horizontal, SpacingTokens.md)
        .padding(.vertical, SpacingTokens.sm)
        .glassPanel(cornerRadius: 999)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private func commitHighlight(colorTag: String) {
        if let rects = pendingPageRects {
            withAnimation(AnimationTokens.quick) {
                session.addHighlight(
                    pageIndex: pageIndex,
                    kind: pendingKind,
                    rects: rects,
                    selectedText: pendingText,
                    colorTag: colorTag,
                    styleTag: pendingStyle
                )
            }
        }
        dismissPicker()
    }

    private func dismissPicker() {
        pendingPageRects = nil
        pendingText = nil
        pickerAnchor = nil
    }

    private func clampedPickerPosition(_ anchor: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(anchor.x, 120), displayedSize.width - 120),
            y: min(max(anchor.y - 36, 24), displayedSize.height - 24)
        )
    }

    // MARK: - Coordinate mapping (view: top-left origin — PDF page: bottom-left origin)

    private func pagePoint(fromViewPoint point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / scale, y: (displayedSize.height - point.y) / scale)
    }

    private func viewRect(fromPageRect rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX * scale,
            y: displayedSize.height - rect.maxY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    private func pageRect(fromViewRect rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX / scale,
            y: (displayedSize.height - rect.maxY) / scale,
            width: rect.width / scale,
            height: rect.height / scale
        )
    }
}

/// The physical-bookmark ribbon shown on bookmarked pages.
struct BookmarkRibbon: View {
    var body: some View {
        Image(systemName: "bookmark.fill")
            .font(.system(size: 22))
            .foregroundStyle(Color(red: 0.78, green: 0.35, blue: 0.28))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .offset(y: -2)
            .accessibilityLabel(Text("Bookmarked"))
    }
}
