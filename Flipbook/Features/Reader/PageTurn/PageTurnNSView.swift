import AppKit
import FlipbookCore
import QuartzCore

/// The book reading surface: a two-page spread with a cover board, center spine, and
/// stacked page-edge hints, where turning a page is a genuine two-sided flip over the
/// spine, tracked 1:1 by trackpad drags and spring-settled on release.
///
/// Interaction notes learned the hard way:
/// - Trackpad `.began` events usually carry a zero delta, so turn direction is decided
///   only after accumulated movement passes a threshold (`.pending` state).
/// - Flip faces are staged synchronously from `stagedImages` (pre-warmed around the
///   current spread); a face whose bitmap is still rendering shows blank paper and is
///   filled in mid-gesture the moment the render lands — never a stall, never a stale page.
/// - Live window resize only moves layer frames (bitmaps stretch transiently, letterboxed
///   by aspect-fit gravity); re-rendering is debounced until the resize settles. Restaging
///   never clears a bitmap until its replacement has arrived.
/// - Narrow windows use single-page layout but still flip (hinged at the page's left
///   edge, blank verso). Crossfade remains only for layout changes (e.g. the cover),
///   far jumps, and Reduce Motion.
@MainActor
final class PageTurnNSView: NSView {
    // MARK: State

    private enum TurnState {
        case idle
        case pending(deltaSum: CGFloat)
        case dragging(forward: Bool)
        case settling(forward: Bool)
    }

    private var state: TurnState = .idle
    private var dragProgress: CGFloat = 0
    private var lastDeltaX: CGFloat = 0
    private var lastDragTimestamp: TimeInterval = 0
    private var dragVelocity: CGFloat = 0 // progress units per second

    private(set) var displayedSpread = 0
    private var session: ReadingSession?
    private var themeID = "warmPaper"
    var swipeGestureEnabled = true

    var onPageCommitted: ((Int) -> Void)?

    var displayedIndex: Int {
        guard let session else { return 0 }
        return BookSpreadLayout.committedIndex(forSpread: displayedSpread, pageCount: session.pageCount)
    }

    // MARK: Image staging

    /// Pre-rendered page bitmaps for the current spread and its neighbors. Entries are
    /// replaced in place when a sharper render lands and pruned only when a page leaves
    /// the staging window — so a stale bitmap is always available to show while its
    /// replacement renders.
    private var stagedImages: [Int: CGImage] = [:]
    /// Which page each flip face is currently showing, so late-arriving renders can be
    /// applied mid-gesture.
    private var flipFrontIndex: Int?
    private var flipBackIndex: Int?

    private var stageGeneration = 0
    private var renderTask: Task<Void, Never>?
    private var restageDebounce: Task<Void, Never>?
    private var lastStagedSize: CGSize = .zero

    // MARK: Layers

    private let bookBoardLayer = CAGradientLayer()
    private let leftEdgesLayer = CAGradientLayer()
    private let rightEdgesLayer = CAGradientLayer()
    private let leftPageLayer = CALayer()
    private let rightPageLayer = CALayer()
    private let spineLayer = CAGradientLayer()
    private let castShadowLayer = CAGradientLayer()
    private let flipContainerLayer = CATransformLayer()
    private let flipFrontLayer = CALayer()
    private let flipBackLayer = CALayer()
    private let flipFrontShading = CAGradientLayer()
    private let flipBackShading = CAGradientLayer()

    // MARK: Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        // A soft diagonal sheen keeps the cover board from reading as flat plastic.
        bookBoardLayer.startPoint = CGPoint(x: 0.1, y: 1)
        bookBoardLayer.endPoint = CGPoint(x: 0.9, y: 0)
        bookBoardLayer.cornerRadius = 10
        bookBoardLayer.shadowColor = CGColor(gray: 0, alpha: 1)
        bookBoardLayer.shadowRadius = 24
        bookBoardLayer.shadowOffset = CGSize(width: 0, height: -12)
        bookBoardLayer.shadowOpacity = 0.38
        bookBoardLayer.borderWidth = 0.5

        for edges in [leftEdgesLayer, rightEdgesLayer] {
            edges.startPoint = CGPoint(x: 0, y: 0.5)
            edges.endPoint = CGPoint(x: 1, y: 0.5)
            edges.cornerRadius = 2
        }

        for page in [leftPageLayer, rightPageLayer, flipFrontLayer, flipBackLayer] {
            // Rects are computed per page aspect, so aspect-fit is normally edge-to-edge;
            // it only letterboxes transiently mid-resize, instead of stretching.
            page.contentsGravity = .resizeAspect
            page.minificationFilter = .trilinear
            page.isDoubleSided = false
        }

        spineLayer.startPoint = CGPoint(x: 0, y: 0.5)
        spineLayer.endPoint = CGPoint(x: 1, y: 0.5)
        spineLayer.colors = [
            CGColor(gray: 0, alpha: 0),
            CGColor(gray: 0, alpha: 0.16),
            CGColor(gray: 0, alpha: 0.28),
            CGColor(gray: 0, alpha: 0.16),
            CGColor(gray: 0, alpha: 0),
        ]

        // Shadow the lifting page casts on the page beneath it — the single strongest
        // depth cue in a real page turn. Anchored at the spine, fading outward.
        castShadowLayer.startPoint = CGPoint(x: 0, y: 0.5)
        castShadowLayer.endPoint = CGPoint(x: 1, y: 0.5)
        castShadowLayer.opacity = 0

        // Paper self-shading: each face darkens toward the spine as it approaches
        // vertical, as if dipping out of the room's light.
        for shading in [flipFrontShading, flipBackShading] {
            shading.startPoint = CGPoint(x: 0, y: 0.5)
            shading.endPoint = CGPoint(x: 1, y: 0.5)
            shading.opacity = 0
        }
        flipFrontLayer.addSublayer(flipFrontShading)
        flipBackLayer.addSublayer(flipBackShading)

        flipBackLayer.transform = CATransform3DMakeRotation(.pi, 0, 1, 0)
        flipContainerLayer.addSublayer(flipFrontLayer)
        flipContainerLayer.addSublayer(flipBackLayer)
        flipContainerLayer.isHidden = true

        guard let rootLayer = layer else { return }
        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / 1600.0
        rootLayer.sublayerTransform = perspective

        rootLayer.addSublayer(bookBoardLayer)
        rootLayer.addSublayer(leftEdgesLayer)
        rootLayer.addSublayer(rightEdgesLayer)
        rootLayer.addSublayer(leftPageLayer)
        rootLayer.addSublayer(rightPageLayer)
        rootLayer.addSublayer(castShadowLayer)
        rootLayer.addSublayer(spineLayer)
        rootLayer.addSublayer(flipContainerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(session: ReadingSession) {
        self.session = session
        displayedSpread = BookSpreadLayout.spread(containing: session.currentPageIndex)
        needsLayout = true
    }

    private var renderScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = renderScale
        for sublayer in [bookBoardLayer, leftEdgesLayer, rightEdgesLayer, spineLayer,
                         castShadowLayer, flipFrontShading, flipBackShading,
                         leftPageLayer, rightPageLayer, flipFrontLayer, flipBackLayer] {
            sublayer.contentsScale = scale
        }
        restageImages()
    }

    func update(themeID: String, pageBackground: CGColor, canvas: CGColor, isDark: Bool) {
        let themeChanged = themeID != self.themeID
        self.themeID = themeID
        layer?.backgroundColor = canvas

        if isDark {
            bookBoardLayer.colors = [
                CGColor(red: 0.10, green: 0.09, blue: 0.09, alpha: 1),
                CGColor(red: 0.16, green: 0.14, blue: 0.13, alpha: 1),
            ]
            bookBoardLayer.borderColor = CGColor(gray: 1, alpha: 0.08)
        } else {
            bookBoardLayer.colors = [
                CGColor(red: 0.20, green: 0.16, blue: 0.13, alpha: 1),
                CGColor(red: 0.33, green: 0.26, blue: 0.20, alpha: 1),
            ]
            bookBoardLayer.borderColor = CGColor(gray: 0, alpha: 0.25)
        }

        let paperEdge = isDark ? 0.32 : 0.88
        let paperEdgeDark = isDark ? 0.16 : 0.62
        leftEdgesLayer.colors = [
            CGColor(gray: paperEdgeDark, alpha: 1),
            CGColor(gray: paperEdge, alpha: 1),
        ]
        rightEdgesLayer.colors = [
            CGColor(gray: paperEdge, alpha: 1),
            CGColor(gray: paperEdgeDark, alpha: 1),
        ]

        // Shading strength tuned per scheme: dark paper needs less added shadow.
        let shadeAlpha: CGFloat = isDark ? 0.42 : 0.34
        castShadowLayer.colors = [
            CGColor(gray: 0, alpha: shadeAlpha),
            CGColor(gray: 0, alpha: shadeAlpha * 0.45),
            CGColor(gray: 0, alpha: 0),
        ]
        for shading in [flipFrontShading, flipBackShading] {
            shading.colors = [
                CGColor(gray: 0, alpha: shadeAlpha * 0.8),
                CGColor(gray: 0, alpha: 0.02),
            ]
        }

        for page in [leftPageLayer, rightPageLayer, flipFrontLayer, flipBackLayer] {
            page.backgroundColor = pageBackground
        }

        if themeChanged {
            // Old-theme bitmaps stay up while the new theme renders in behind them.
            restageImages()
        }
    }

    // MARK: Layout

    private func layout(forSpread spread: Int) -> BookSpreadLayout {
        guard let session else {
            return BookSpreadLayout.compute(
                bounds: bounds.size, spread: 0, pageCount: 0, pageSize: CGSize(width: 612, height: 792)
            )
        }
        return BookSpreadLayout.compute(
            bounds: bounds.size,
            spread: spread,
            pageCount: session.pageCount
        ) { session.document.pageSize(at: $0) }
    }

    private var currentLayout: BookSpreadLayout { layout(forSpread: displayedSpread) }

    override func layout() {
        super.layout()
        guard bounds.width > 100, bounds.height > 80 else { return }
        let spreadLayout = currentLayout

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        bookBoardLayer.frame = spreadLayout.bookRect
        // Explicit shadow path: without one, Core Animation re-derives the shadow from
        // the layer's alpha every frame of the 3D flip — the main historical jank source.
        bookBoardLayer.shadowPath = CGPath(
            roundedRect: CGRect(origin: .zero, size: spreadLayout.bookRect.size),
            cornerWidth: bookBoardLayer.cornerRadius,
            cornerHeight: bookBoardLayer.cornerRadius,
            transform: nil
        )
        leftPageLayer.frame = spreadLayout.leftRect
        rightPageLayer.frame = spreadLayout.rightRect
        leftPageLayer.isHidden = spreadLayout.isSingle || spreadLayout.leftPageIndex == nil

        let fraction = readFraction
        let maxEdge: CGFloat = 12
        let leftThickness = spreadLayout.isSingle ? 0 : max(maxEdge * fraction, 1)
        let rightThickness = spreadLayout.isSingle ? 0 : max(maxEdge * (1 - fraction), 1)
        leftEdgesLayer.frame = CGRect(
            x: spreadLayout.leftRect.minX - leftThickness,
            y: spreadLayout.leftRect.minY + 3,
            width: leftThickness,
            height: spreadLayout.leftRect.height - 6
        )
        rightEdgesLayer.frame = CGRect(
            x: spreadLayout.rightRect.maxX,
            y: spreadLayout.rightRect.minY + 3,
            width: rightThickness,
            height: spreadLayout.rightRect.height - 6
        )
        leftEdgesLayer.isHidden = spreadLayout.isSingle
        rightEdgesLayer.isHidden = spreadLayout.isSingle

        let spineWidth: CGFloat = min(72, spreadLayout.rightRect.width * 0.24)
        spineLayer.frame = CGRect(
            x: spreadLayout.rightRect.minX - spineWidth / 2,
            y: spreadLayout.rightRect.minY,
            width: spineWidth,
            height: spreadLayout.rightRect.height
        )
        spineLayer.isHidden = spreadLayout.isSingle

        CATransaction.commit()

        // Frames just moved (bitmaps scale with them); only re-render once the size
        // stops changing. First layout at a new size renders immediately.
        if lastStagedSize == .zero {
            restageImages()
        } else if bounds.size != lastStagedSize {
            restageDebounce?.cancel()
            restageDebounce = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(160))
                guard let self, !Task.isCancelled else { return }
                self.restageImages()
            }
        }
    }

    private func layoutFlipContainer(for spreadLayout: BookSpreadLayout, forward: Bool) {
        // Spread mode hinges on the spine; single-page mode always hinges on the page's
        // left edge (a stack of sheets bound at the left).
        let rect: CGRect
        let anchorX: CGFloat
        if spreadLayout.isSingle {
            rect = spreadLayout.rightRect
            anchorX = 0
        } else {
            rect = forward ? spreadLayout.rightRect : spreadLayout.leftRect
            anchorX = forward ? 0 : 1
        }
        flipContainerLayer.bounds = CGRect(origin: .zero, size: rect.size)
        flipContainerLayer.anchorPoint = CGPoint(x: anchorX, y: 0.5)
        flipContainerLayer.position = CGPoint(
            x: anchorX == 0 ? rect.minX : rect.maxX,
            y: rect.midY
        )
        let faceFrame = CGRect(origin: .zero, size: rect.size)
        flipFrontLayer.frame = faceFrame
        flipBackLayer.frame = faceFrame
        flipFrontShading.frame = CGRect(origin: .zero, size: rect.size)
        flipBackShading.frame = CGRect(origin: .zero, size: rect.size)

        // Shading and cast shadow both emanate from the hinge.
        let towardHinge = anchorX == 0
        flipFrontShading.startPoint = CGPoint(x: towardHinge ? 0 : 1, y: 0.5)
        flipFrontShading.endPoint = CGPoint(x: towardHinge ? 1 : 0, y: 0.5)
        // The back face is mirrored by its π rotation, so its gradient flips too.
        flipBackShading.startPoint = CGPoint(x: towardHinge ? 1 : 0, y: 0.5)
        flipBackShading.endPoint = CGPoint(x: towardHinge ? 0 : 1, y: 0.5)

        // Cast shadow sits over the page being revealed beneath the lifting sheet.
        let shadowRect: CGRect
        if spreadLayout.isSingle {
            shadowRect = spreadLayout.rightRect
            castShadowLayer.startPoint = CGPoint(x: 0, y: 0.5)
            castShadowLayer.endPoint = CGPoint(x: 1, y: 0.5)
        } else if forward {
            shadowRect = spreadLayout.rightRect
            castShadowLayer.startPoint = CGPoint(x: 0, y: 0.5)
            castShadowLayer.endPoint = CGPoint(x: 1, y: 0.5)
        } else {
            shadowRect = spreadLayout.leftRect
            castShadowLayer.startPoint = CGPoint(x: 1, y: 0.5)
            castShadowLayer.endPoint = CGPoint(x: 0, y: 0.5)
        }
        castShadowLayer.frame = shadowRect
    }

    private var readFraction: CGFloat {
        guard let session, session.pageCount > 1 else { return 0 }
        return CGFloat(displayedIndex) / CGFloat(session.pageCount - 1)
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: Image staging

    /// Re-renders the staging window (current spread first, then next, then previous).
    /// Existing bitmaps are kept on screen until each replacement arrives, and results
    /// landing mid-gesture are applied straight onto the active flip faces.
    private func restageImages() {
        guard let session, bounds.width > 100 else { return }
        lastStagedSize = bounds.size
        restageDebounce?.cancel()

        stageGeneration += 1
        let generation = stageGeneration
        let themeID = self.themeID
        let scale = renderScale

        // Per-spread layouts so each page renders at the rect its own aspect produces.
        var wanted: [(index: Int, width: CGFloat)] = []
        for spread in [displayedSpread, displayedSpread + 1, displayedSpread - 1] {
            guard spread >= 0, spread < BookSpreadLayout.spreadCount(pageCount: session.pageCount) else { continue }
            let spreadLayout = layout(forSpread: spread)
            let pages = BookSpreadLayout.pages(inSpread: spread, pageCount: session.pageCount)
            if let left = pages.left { wanted.append((left, spreadLayout.leftRect.width)) }
            if let right = pages.right { wanted.append((right, spreadLayout.rightRect.width)) }
        }

        // Prune pages that left the staging window; never clear ones still in it.
        let wantedIndices = Set(wanted.map(\.index))
        stagedImages = stagedImages.filter { wantedIndices.contains($0.key) }

        renderTask?.cancel()
        renderTask = Task { [weak self] in
            for (index, width) in wanted {
                guard let self, !Task.isCancelled, self.stageGeneration == generation,
                      let session = self.session
                else { return }
                let zoom = width / max(session.document.pageSize(at: index).width, 1)
                // Cache hits return instantly; only genuinely new (page, zoom, theme)
                // combinations pay for a render.
                let image = await session.renderer.image(
                    pageIndex: index, zoom: zoom, themeID: themeID, screenScale: scale
                )
                guard self.stageGeneration == generation, let image else { continue }
                self.stagedImages[index] = image
                self.applyStagedImage(image, forPage: index)
            }
        }
    }

    /// Routes a freshly rendered bitmap to whichever layer is showing that page right
    /// now — resting pages when idle, flip faces mid-gesture.
    private func applyStagedImage(_ image: CGImage, forPage index: Int) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if case .idle = state {
            let spreadLayout = currentLayout
            if spreadLayout.leftPageIndex == index && !spreadLayout.isSingle {
                leftPageLayer.contents = image
            }
            let rightIndex = spreadLayout.rightPageIndex ?? spreadLayout.leftPageIndex
            if rightIndex == index {
                rightPageLayer.contents = image
            }
            return
        }

        if flipFrontIndex == index { flipFrontLayer.contents = image }
        if flipBackIndex == index { flipBackLayer.contents = image }
        // The page being revealed under the flip also fills in as it lands.
        guard let session else { return }
        let forward: Bool
        switch state {
        case .dragging(let f), .settling(let f): forward = f
        default: return
        }
        let target = BookSpreadLayout.pages(
            inSpread: displayedSpread + (forward ? 1 : -1), pageCount: session.pageCount
        )
        if forward, target.right == index || (currentLayout.isSingle && (target.right ?? target.left) == index) {
            rightPageLayer.contents = image
        }
        if !forward, target.left == index {
            leftPageLayer.contents = image
        }
    }

    /// Refreshes the resting page layers from staged bitmaps (blank paper when absent).
    private func applyRestingContents() {
        guard case .idle = state else { return }
        let spreadLayout = currentLayout
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        leftPageLayer.contents = spreadLayout.leftPageIndex.flatMap { stagedImages[$0] }
        let rightIndex = spreadLayout.rightPageIndex ?? spreadLayout.leftPageIndex
        rightPageLayer.contents = rightIndex.flatMap { stagedImages[$0] }
        CATransaction.commit()
    }

    // MARK: External navigation

    func navigate(to pageIndex: Int) {
        guard case .idle = state, let session else { return }
        let clamped = min(max(pageIndex, 0), max(session.pageCount - 1, 0))
        let targetSpread = BookSpreadLayout.spread(containing: clamped)
        guard targetSpread != displayedSpread else { return }

        let step = targetSpread - displayedSpread
        if abs(step) == 1 && canFlip(forward: step > 0) {
            startProgrammaticFlip(forward: step > 0)
        } else {
            crossfade(toSpread: targetSpread)
        }
    }

    /// Flips need the same layout shape on both sides of the turn; the cover page
    /// (centered, single) transitioning to a spread crossfades instead.
    private func canFlip(forward: Bool) -> Bool {
        guard let session, !reduceMotion else { return false }
        let targetSpread = displayedSpread + (forward ? 1 : -1)
        guard targetSpread >= 0,
              targetSpread < BookSpreadLayout.spreadCount(pageCount: session.pageCount)
        else { return false }
        return layout(forSpread: targetSpread).isSingle == currentLayout.isSingle
    }

    // MARK: Trackpad

    override func scrollWheel(with event: NSEvent) {
        guard swipeGestureEnabled, session != nil else { return }

        switch event.phase {
        case .began:
            gestureBegan()
        case .changed:
            gestureMoved(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, timestamp: event.timestamp)
        case .ended, .cancelled:
            gestureEnded()
        default:
            break
        }
    }

    // Click-and-drag turns pages too — not everyone reaches for a two-finger swipe.
    override func mouseDown(with event: NSEvent) {
        guard session != nil else { return }
        gestureBegan()
    }

    override func mouseDragged(with event: NSEvent) {
        gestureMoved(deltaX: event.deltaX, deltaY: event.deltaY, timestamp: event.timestamp)
    }

    override func mouseUp(with event: NSEvent) {
        gestureEnded()
    }

    private func gestureBegan() {
        guard case .idle = state else { return }
        // Direction can't be trusted yet — initial deltas are usually zero.
        state = .pending(deltaSum: 0)
        lastDeltaX = 0
        dragVelocity = 0
        lastDragTimestamp = 0
    }

    private func gestureMoved(deltaX: CGFloat, deltaY: CGFloat, timestamp: TimeInterval) {
        switch state {
        case .pending(let deltaSum):
            let sum = deltaSum + deltaX
            lastDeltaX = deltaX
            if abs(sum) > 4 {
                if abs(deltaY) > abs(sum) * 2 {
                    state = .idle // predominantly vertical — not a page turn
                } else {
                    beginDrag(forward: sum < 0, initialDelta: sum)
                    lastDragTimestamp = timestamp
                }
            } else {
                state = .pending(deltaSum: sum)
            }
        case .dragging(let forward):
            lastDeltaX = deltaX
            let delta = -deltaX / max(bounds.width * 0.55, 1) * (forward ? 1 : -1)
            let previous = dragProgress
            dragProgress = min(max(dragProgress + delta, 0), 1)
            if lastDragTimestamp > 0, timestamp > lastDragTimestamp {
                let instantaneous = (dragProgress - previous) / CGFloat(timestamp - lastDragTimestamp)
                // Light smoothing so one jittery event doesn't dictate the release spring.
                dragVelocity = dragVelocity * 0.7 + instantaneous * 0.3
            }
            lastDragTimestamp = timestamp
            applyFlip(progress: dragProgress, forward: forward)
        default:
            break
        }
    }

    private func gestureEnded() {
        switch state {
        case .pending:
            state = .idle
        case .dragging(let forward):
            let flung = forward ? lastDeltaX < -5 : lastDeltaX > 5
            settleFlip(forward: forward, commit: dragProgress > 0.3 || flung)
        default:
            break
        }
    }

    private func beginDrag(forward: Bool, initialDelta: CGFloat) {
        guard let session else {
            state = .idle
            return
        }
        let targetSpread = displayedSpread + (forward ? 1 : -1)
        guard targetSpread >= 0,
              targetSpread < BookSpreadLayout.spreadCount(pageCount: session.pageCount)
        else {
            state = .idle
            return
        }

        if !canFlip(forward: forward) {
            crossfade(toSpread: targetSpread)
            return
        }

        state = .dragging(forward: forward)
        dragProgress = min(max(-initialDelta / max(bounds.width * 0.55, 1) * (forward ? 1 : -1), 0), 1)
        stageFlip(forward: forward)
        applyFlip(progress: dragProgress, forward: forward)
    }

    /// Synchronous staging from `stagedImages` — a face whose render hasn't landed yet
    /// shows the page background (blank paper) and is filled by `applyStagedImage` the
    /// moment it does; never a stall or a broken gesture.
    private func stageFlip(forward: Bool) {
        guard let session else { return }
        let spreadLayout = currentLayout
        let target = BookSpreadLayout.pages(
            inSpread: displayedSpread + (forward ? 1 : -1),
            pageCount: session.pageCount
        )
        let current = BookSpreadLayout.pages(inSpread: displayedSpread, pageCount: session.pageCount)

        layoutFlipContainer(for: spreadLayout, forward: forward)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if spreadLayout.isSingle {
            // Single sheet hinged at the left: forward turns the current page away
            // (blank verso), backward brings the previous page in over it.
            let currentIndex = current.right ?? current.left
            let targetIndex = target.right ?? target.left
            if forward {
                flipFrontIndex = currentIndex
                flipBackIndex = nil
                rightPageLayer.contents = targetIndex.flatMap { stagedImages[$0] }
            } else {
                flipFrontIndex = targetIndex
                flipBackIndex = nil
            }
        } else if forward {
            flipFrontIndex = current.right
            flipBackIndex = target.left
            rightPageLayer.contents = target.right.flatMap { stagedImages[$0] }
        } else {
            flipFrontIndex = current.left
            flipBackIndex = target.right
            leftPageLayer.contents = target.left.flatMap { stagedImages[$0] }
        }
        flipFrontLayer.contents = flipFrontIndex.flatMap { stagedImages[$0] }
        flipBackLayer.contents = flipBackIndex.flatMap { stagedImages[$0] }
        flipContainerLayer.isHidden = false
        castShadowLayer.opacity = 0
        applyFlip(progress: dragProgress, forward: forward)
        CATransaction.commit()
    }

    // MARK: Flip geometry

    private func flipAngle(progress: CGFloat, forward: Bool) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        if currentLayout.isSingle {
            // Both directions hinge left: forward folds the sheet away (0 → -π),
            // backward brings the previous sheet down onto the stack (-π → 0).
            return forward ? -CGFloat.pi * clamped : -CGFloat.pi * (1 - clamped)
        }
        return (forward ? -1 : 1) * CGFloat.pi * clamped
    }

    /// Sets the flip transform plus every progress-driven depth cue in one transaction.
    private func applyFlip(progress: CGFloat, forward: Bool) {
        let clamped = min(max(progress, 0), 1)
        // Lift of the sheet off the book, 0 → 1 → 0 across the turn.
        let lift = sin(clamped * .pi)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        flipContainerLayer.transform = CATransform3DMakeRotation(
            flipAngle(progress: clamped, forward: forward), 0, 1, 0
        )
        spineLayer.opacity = Float(0.9 + 0.7 * lift)

        // Front face shades in as the page rises (first half); the back face starts
        // fully shaded at vertical and brightens as it lays down (second half).
        flipFrontShading.opacity = Float(min(clamped * 2, 1) * lift)
        flipBackShading.opacity = Float(min((1 - clamped) * 2, 1) * lift)

        // Cast shadow is strongest just past vertical, when the sheet hangs over
        // the revealed page.
        castShadowLayer.opacity = Float(lift * 0.9)
        CATransaction.commit()
    }

    // MARK: Settling

    private func settleFlip(forward: Bool, commit: Bool) {
        state = .settling(forward: forward)
        let target: CGFloat = commit ? 1 : 0
        let finalTransform = CATransform3DMakeRotation(
            flipAngle(progress: target, forward: forward), 0, 1, 0
        )

        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = flipContainerLayer.presentation()?.transform ?? flipContainerLayer.transform
        spring.toValue = finalTransform
        spring.damping = 32
        spring.stiffness = 260
        spring.mass = 1
        // Carry the finger's speed into the spring so a flung page keeps its momentum.
        let remaining = abs(target - dragProgress)
        if remaining > 0.01 {
            let directionalVelocity = commit ? max(dragVelocity, 0) : max(-dragVelocity, 0)
            spring.initialVelocity = min(directionalVelocity / remaining, 12)
        }
        spring.duration = spring.settlingDuration

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.finishFlip(forward: forward, committed: commit)
            }
        }
        flipContainerLayer.add(spring, forKey: "settle")
        // Set the model value with actions disabled: an implicit transform animation
        // here would race the spring and snap the page partway through the settle.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        flipContainerLayer.transform = finalTransform
        CATransaction.commit()

        // Depth cues fade out over the settle (implicit animations, matched duration).
        CATransaction.setValue(min(spring.settlingDuration, 0.6), forKey: kCATransactionAnimationDuration)
        flipFrontShading.opacity = 0
        flipBackShading.opacity = 0
        castShadowLayer.opacity = 0
        spineLayer.opacity = 0.9
        CATransaction.commit()
    }

    private func finishFlip(forward: Bool, committed: Bool) {
        guard let session else { return }

        if committed {
            displayedSpread += forward ? 1 : -1
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        flipContainerLayer.isHidden = true
        flipContainerLayer.removeAllAnimations()
        flipContainerLayer.transform = CATransform3DIdentity
        flipFrontShading.opacity = 0
        flipBackShading.opacity = 0
        castShadowLayer.opacity = 0
        spineLayer.opacity = 0.9
        CATransaction.commit()

        state = .idle
        dragProgress = 0
        dragVelocity = 0
        flipFrontIndex = nil
        flipBackIndex = nil
        applyRestingContents()
        if committed {
            onPageCommitted?(
                BookSpreadLayout.committedIndex(forSpread: displayedSpread, pageCount: session.pageCount)
            )
            needsLayout = true
        }
        restageImages()
    }

    private func startProgrammaticFlip(forward: Bool) {
        state = .dragging(forward: forward)
        dragProgress = 0.02
        dragVelocity = 2.5 // a hand-turned page, not a fling
        stageFlip(forward: forward)
        settleFlip(forward: forward, commit: true)
    }

    private func crossfade(toSpread spread: Int) {
        guard let session else { return }
        state = .idle
        flipFrontIndex = nil
        flipBackIndex = nil
        displayedSpread = min(max(spread, 0), max(BookSpreadLayout.spreadCount(pageCount: session.pageCount) - 1, 0))

        let fade = CATransition()
        fade.type = .fade
        fade.duration = reduceMotion ? 0.08 : 0.22
        layer?.add(fade, forKey: "crossfade")

        onPageCommitted?(
            BookSpreadLayout.committedIndex(forSpread: displayedSpread, pageCount: session.pageCount)
        )
        needsLayout = true
        applyRestingContents()
        restageImages()
    }
}
