import FlipbookCore
import FlipbookDesignSystem
import SwiftUI

/// Continuous-scroll navigation mode: a lazy vertical stack of rendered pages with
/// book-like inter-page gaps and paper shadows. Pure SwiftUI — each row displays one
/// cached `CGImage`, so scrolling never touches PDFKit.
struct ContinuousScrollView: View {
    let session: ReadingSession
    let theme: ThemeDefinition

    private var themeID: String { theme.id }

    @State private var visiblePageID: Int?

    private let horizontalMargin: CGFloat = SpacingTokens.xl
    private let pageGap: CGFloat = SpacingTokens.lg

    var body: some View {
        GeometryReader { geometry in
            ScrollView(scrollAxes(in: geometry)) {
                LazyVStack(spacing: pageGap) {
                    ForEach(0..<session.pageCount, id: \.self) { index in
                        pageRow(index: index, in: geometry)
                            .id(index)
                    }
                }
                .padding(.vertical, SpacingTokens.xl)
                .frame(maxWidth: .infinity)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $visiblePageID, anchor: .center)
            .onChange(of: visiblePageID) { _, newValue in
                if let newValue {
                    session.setCurrentPage(newValue)
                    prefetchNeighbors(in: geometry)
                }
            }
            .onChange(of: session.scrollToRequest) { _, request in
                guard let request else { return }
                withAnimation(AnimationTokens.standard) {
                    visiblePageID = request.pageIndex
                }
                session.scrollToRequest = nil
            }
            .onAppear {
                visiblePageID = session.currentPageIndex
                prefetchNeighbors(in: geometry)
            }
        }
    }

    /// Warms neighbor pages at the same zoom the rows render at, so the cache
    /// hits when they scroll into view.
    private func prefetchNeighbors(in geometry: GeometryProxy) {
        let index = session.currentPageIndex
        let size = session.document.pageSize(at: index)
        guard size.width > 0 else { return }
        let renderZoom = pageWidth(forPage: index, in: geometry) / size.width
        session.prefetch(renderZoom: renderZoom, themeID: themeID)
    }

    private func scrollAxes(in geometry: GeometryProxy) -> Axis.Set {
        pageWidth(forPage: session.currentPageIndex, in: geometry) > geometry.size.width
            ? [.vertical, .horizontal]
            : .vertical
    }

    private func pageRow(index: Int, in geometry: GeometryProxy) -> some View {
        let width = pageWidth(forPage: index, in: geometry)
        let size = session.document.pageSize(at: index)
        let height = size.width > 0 ? width * size.height / size.width : width * 1.4

        return PageImageView(
            session: session,
            pageIndex: index,
            theme: theme,
            renderZoom: size.width > 0 ? width / size.width : 1
        )
        .frame(width: width, height: height)
        .background(theme.pageColor)
        .overlay(
            PageAnnotationsOverlay(
                session: session,
                pageIndex: index,
                displayedSize: CGSize(width: width, height: height),
                theme: theme
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.22), radius: 10, y: 4)
        .accessibilityLabel(Text("Page \(index + 1) of \(session.pageCount)"))
    }

    /// Base width fits the window with comfortable margins; the user's zoom multiplies it.
    private func pageWidth(forPage index: Int, in geometry: GeometryProxy) -> CGFloat {
        let fitWidth = min(max(geometry.size.width - horizontalMargin * 2, 200), 860)
        return fitWidth * session.zoom
    }
}

/// Displays one rendered page, loading asynchronously from the `PageRenderer` cache.
/// When the theme changes, the previous theme's bitmap stays visible until the new one
/// arrives, then crossfades — no white flash mid-read.
private struct PageImageView: View {
    let session: ReadingSession
    let pageIndex: Int
    let theme: ThemeDefinition
    let renderZoom: CGFloat

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: session.screenScale)
                    .resizable()
                    .interpolation(.high)
            } else {
                Rectangle()
                    .fill(theme.pageColor)
                    .overlay(ProgressView().controlSize(.small).opacity(0.4))
            }
        }
        .animation(AnimationTokens.standard, value: renderTaskKey)
        .task(id: renderTaskKey) {
            image = await session.renderer.image(
                pageIndex: pageIndex,
                zoom: renderZoom,
                themeID: theme.id,
                screenScale: session.screenScale
            )
        }
    }

    private var renderTaskKey: String {
        "\(pageIndex)-\(PageCacheKey.bucket(forZoom: renderZoom))-\(theme.id)"
    }
}
