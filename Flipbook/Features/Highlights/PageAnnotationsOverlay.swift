import FlipbookCore
import FlipbookDesignSystem
import SwiftUI

/// Sits over a displayed page: renders committed highlights and the bookmark ribbon, and —
/// while the highlighter tool is active — hosts a free-roam pen. Dragging lays down a
/// translucent stroke that follows your hand (not a bounding box), like a real highlighter;
/// a tap on an existing mark erases it. The words under a mark are captured for its sidebar
/// snippet. Works identically in scroll and page-turn modes.
struct PageAnnotationsOverlay: View {
    let session: ReadingSession
    let pageIndex: Int
    let displayedSize: CGSize
    let theme: ThemeDefinition

    /// The in-progress stroke, in view space (top-left origin).
    @State private var livePoints: [CGPoint] = []

    private var pageSize: CGSize { session.document.pageSize(at: pageIndex) }
    private var scale: CGFloat { pageSize.width > 0 ? displayedSize.width / pageSize.width : 1 }
    private var active: Bool { session.highlighterActive }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(session.highlights(forPage: pageIndex)) { highlight in
                committedMark(highlight)
            }

            if livePoints.count >= 2 {
                penStroke(
                    viewPoints: livePoints,
                    width: viewPenWidth(session.highlighterStyle),
                    colorID: session.highlighterColorTag,
                    style: session.highlighterStyle
                )
            }

            if session.bookmark(forPage: pageIndex) != nil {
                BookmarkRibbon()
                    .padding(.trailing, SpacingTokens.lg)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(width: displayedSize.width, height: displayedSize.height, alignment: .topTrailing)
        .contentShape(Rectangle())
        .gesture(markerGesture, isEnabled: active)
        .animation(AnimationTokens.quick, value: session.bookmark(forPage: pageIndex) != nil)
    }

    // MARK: - Committed marks

    @ViewBuilder
    private func committedMark(_ highlight: Highlight) -> some View {
        let strokePoints = StrokePath.decode(highlight.strokePointsData)
        if !strokePoints.isEmpty {
            penStroke(
                viewPoints: strokePoints.map(viewPoint(fromPagePoint:)),
                width: CGFloat(highlight.strokeWidth) * scale,
                colorID: highlight.colorTag,
                style: highlight.styleTag
            )
        } else {
            // Legacy rect-based highlights (text selections / regions from older builds).
            ForEach(Array(QuadPoints.decode(highlight.quadPointsData).enumerated()), id: \.offset) { _, pageRect in
                legacyRect(viewRect(fromPageRect: pageRect), colorID: highlight.colorTag, style: highlight.styleTag)
            }
        }
    }

    /// A pen stroke: the path traced through `viewPoints`, stroked with round caps so it
    /// reads as one continuous marker line. Highlight style is thick and translucent
    /// (multiplies into the page); underline style is a thinner, near-opaque line.
    private func penStroke(viewPoints: [CGPoint], width: CGFloat, colorID: String, style: String) -> some View {
        let path = Path { p in
            guard let first = viewPoints.first else { return }
            p.move(to: first)
            for point in viewPoints.dropFirst() { p.addLine(to: point) }
        }
        let underline = style == "underline"
        let color = underline
            ? HighlightPalette.color(for: colorID).opacity(0.9)
            : HighlightPalette.overlayColor(for: colorID, isDarkTheme: theme.isDark)
        return path
            .stroke(color, style: StrokeStyle(lineWidth: max(width, 2), lineCap: .round, lineJoin: .round))
            .blendMode(underline ? .normal : (theme.isDark ? .screen : .multiply))
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func legacyRect(_ rect: CGRect, colorID: String, style: String) -> some View {
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

    // MARK: - Pen gesture

    /// A drag traces a stroke; a near-stationary press (a tap) erases the mark under it.
    private var markerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                appendPoint(value.location, start: value.startLocation)
            }
            .onEnded { value in
                let points = livePoints
                livePoints = []
                if polylineLength(points) < 6 {
                    eraseMark(at: value.location)
                } else {
                    commitStroke(points)
                }
            }
    }

    /// Samples the drag path, dropping points closer than ~1.5pt so the stored stroke stays
    /// compact without visibly faceting.
    private func appendPoint(_ point: CGPoint, start: CGPoint) {
        if livePoints.isEmpty { livePoints.append(start) }
        guard let last = livePoints.last else { return }
        if hypot(point.x - last.x, point.y - last.y) >= 1.5 {
            livePoints.append(point)
        }
    }

    private func commitStroke(_ viewPoints: [CGPoint]) {
        guard viewPoints.count >= 2 else { return }
        let style = session.highlighterStyle
        let pagePoints = viewPoints.map(pagePoint(fromViewPoint:))
        let pageWidth = viewPenWidth(style) / max(scale, 0.01)
        let box = boundingBox(pagePoints)
            .insetBy(dx: -pageWidth / 2, dy: -pageWidth / 2)
            .intersection(CGRect(origin: .zero, size: pageSize))
        let snippet = session.document.text(inRect: box, pageIndex: pageIndex)
        withAnimation(AnimationTokens.quick) {
            session.addPenHighlight(
                pageIndex: pageIndex,
                strokePoints: pagePoints,
                strokeWidth: pageWidth,
                boundingBox: box,
                selectedText: snippet,
                colorTag: session.highlighterColorTag,
                styleTag: style
            )
        }
    }

    private func eraseMark(at point: CGPoint) {
        let hit = session.highlights(forPage: pageIndex).first { highlight in
            let stroke = StrokePath.decode(highlight.strokePointsData)
            if !stroke.isEmpty {
                let viewStroke = stroke.map(viewPoint(fromPagePoint:))
                let tolerance = max(CGFloat(highlight.strokeWidth) * scale, 10) / 2 + 6
                return distanceToPolyline(point, viewStroke) <= tolerance
            }
            return QuadPoints.decode(highlight.quadPointsData).contains {
                viewRect(fromPageRect: $0).insetBy(dx: -6, dy: -6).contains(point)
            }
        }
        guard let hit else { return }
        withAnimation(AnimationTokens.quick) {
            session.removeHighlight(hit)
        }
    }

    /// Fixed view-space pen thickness so a stroke feels the same regardless of zoom; it's
    /// converted to page space at commit and scales with the page thereafter.
    private func viewPenWidth(_ style: String) -> CGFloat {
        style == "underline" ? 5 : 18
    }

    // MARK: - Geometry helpers

    private func polylineLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    private func boundingBox(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); minY = min(minY, point.y)
            maxX = max(maxX, point.x); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func distanceToPolyline(_ point: CGPoint, _ line: [CGPoint]) -> CGFloat {
        guard line.count >= 2 else {
            return line.first.map { hypot(point.x - $0.x, point.y - $0.y) } ?? .greatestFiniteMagnitude
        }
        return zip(line, line.dropFirst()).reduce(CGFloat.greatestFiniteMagnitude) { best, segment in
            min(best, distanceToSegment(point, segment.0, segment.1))
        }
    }

    private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    // MARK: - Coordinate mapping (view: top-left origin — PDF page: bottom-left origin)

    private func viewPoint(fromPagePoint point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale, y: displayedSize.height - point.y * scale)
    }

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
