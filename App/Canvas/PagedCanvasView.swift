import LinedInk
import LinedLayout
import LinedModel
import LinedRendering
import PencilKit
import UIKit

/// What a paged canvas needs from, and reports to, the notebook it shows.
protocol PagedCanvasDelegate: AnyObject {
    /// What the system's undo gestures and keyboard shortcuts act on while the canvas has the focus.
    var undoManager: NotebookUndoManager { get }
    func backgroundRenderer(for page: Page) -> any PageBackgroundRenderer
    /// The stored ink of a page that comes near the viewport, in page points. The canvas shows it
    /// until it reports `canvasDidEndDisplayingInk(of:)`.
    func ink(for pageID: Page.ID) async -> [PKStroke]
    func canvasDidEndDisplayingInk(of pageID: Page.ID)
    /// The ink of these pages changed by drawing, erasing or moving strokes.
    func canvasDidChangeInk(_ changes: [PageInkChange])
    func canvasDidShowPage(at index: Int)
}

/// The commands a notebook sends to the canvas that shows it.
protocol PagedCanvasControlling: AnyObject {
    func setPages(_ pages: [Page])
    /// Reports at once the ink that the canvas would report when the writing pauses. What the
    /// notebook does next, like saving or undoing, then starts from all that was drawn.
    func reportPendingInk()
    /// Replaces the ink of a page with what an undone or redone step left there, in page points.
    func setInk(_ strokes: [PKStroke], for pageID: Page.ID)
    func scroll(to pageID: Page.ID, animated: Bool)
    /// Scrolls to the page unless part of it is already in view.
    func reveal(_ pageID: Page.ID)
}

/// Scrolls and zooms the pages of a notebook as one continuous vertical stack and takes the handwriting.
///
/// A single PencilKit canvas is the scroll view of the whole notebook, so scrolling, zooming and ink
/// rendering are PencilKit's own. The canvas draws in document points. The page backgrounds lie beneath
/// its ink and follow its zoom.
///
/// Only the pages near the viewport have a view, and only they have their ink in the canvas: what
/// PencilKit holds, renders and analyses follows the screen and not the length of the notebook.
final class PagedCanvasView: UIView {
    weak var delegate: (any PagedCanvasDelegate)? {
        didSet { canvas.notebookUndoManager = delegate?.undoManager }
    }

    /// Called when the pencil or a finger starts to draw, erase or select.
    var onToolBegin: (() -> Void)?
    /// Called when a stroke of the eraser ends.
    var onEraseEnd: (() -> Void)?
    /// Called with what the user set a double tap on Apple Pencil to do.
    var onPencilShortcut: ((PencilShortcut) -> Void)?

    var tools = ToolSettings() {
        didSet {
            if tools != oldValue { applyTool() }
        }
    }

    private enum ZoomLimit {
        static let minimumRelativeToFit: CGFloat = 0.5
        static let maximumRelativeToFit: CGFloat = 5
        /// PencilKit magnifies its canvas no further.
        static let maximum: CGFloat = 10
    }

    /// How far around the viewport the canvas holds ink, in viewport heights.
    private enum InkReach {
        /// Pages this close have their ink loaded before they scroll into view.
        static let load: CGFloat = 1
        /// Pages farther away give their ink up. The distance to `load` keeps a page from loading
        /// and unloading while the view moves back and forth.
        static let keep: CGFloat = 2
        /// While the view scrolls, pages give their ink up this many at a time: taking ink out of
        /// the canvas costs as much for one page as for several.
        static let pagesReleasedTogether = 4
    }

    /// How long the ink is left alone after a tool has lifted or the ink has changed, before the
    /// canvas reads it and replaces it. PencilKit finishes a stroke shortly after the tool has lifted,
    /// and the stroke must find the ink it was drawn on. Reading the ink takes time with every stroke
    /// the canvas holds, so it waits for a pause in the writing as well.
    private static let inkSettlingTime = Duration.milliseconds(120)

    /// Room below the last page, so that its end can be scrolled clear of a tool bar docked at the bottom.
    private static let bottomClearance: CGFloat = 96

    private static let deskColor = UIColor.secondarySystemBackground

    /// Document points per page point. PencilKit draws no even line thinner than 0.5 of its points,
    /// so the canvas draws pages at twice their size to allow lines half as thin on the page.
    static let documentScale: CGFloat = 2

    private let canvas = InkCanvasView()
    /// Holds the page backgrounds beneath the ink, laid out in document points.
    private let pagesView = UIView()
    private let desk = DeskView()
    private let eraserIndicator = EraserIndicator()
    private let renderPool = BackgroundRenderPool()

    private var pages: [Page] = []
    private var pageIDs: [Page.ID] = []
    private var indexByPageID: [Page.ID: Int] = [:]
    private var layout = PageStackLayout(pageSizes: [], scale: documentScale)
    private var pageViews: [Page.ID: PageBackgroundView] = [:]
    private var reusablePageViews: [PageBackgroundView] = []
    private var viewportSize = CGSize.zero
    private var isZooming = false
    private var isApplyingLayout = false
    private var isReplacingInk = false
    /// The pages whose ink is in the canvas, with that ink as it was last reported.
    private var inkRecord = CanvasInk<Page.ID, PKStroke>()
    /// Pages whose stored ink has been asked for and has not arrived.
    private var inkRequests: Set<Page.ID> = []
    /// Stored ink that arrived while the canvas could not take it.
    private var arrivedInk: [Page.ID: [PKStroke]] = [:]
    /// Pages that were drawn on before their stored ink arrived.
    private var pagesDrawnOnEarly: Set<Page.ID> = []
    private var isToolInUse = false
    private var hasUnreportedInk = false
    /// The strokes of the canvas when the record last agreed with all of them: how many there were
    /// and which was the last. Strokes drawn since lie on top of these and are told apart by that,
    /// without a look at the rest of the ink. `nil` when more than drawing may have changed the ink.
    private var reportedInk: (count: Int, lastID: UUID?)?
    /// Runs while the ink settles after a tool was used or the ink has changed.
    private var inkSettling: Task<Void, Never>?
    private var hasErased = false
    private var keyboardObserver: (any NSObjectProtocol)?
    private var currentPageIndex: Int?
    private var pendingScrollTarget: Page.ID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Self.deskColor

        canvas.delegate = self
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.alwaysBounceVertical = true
        // Paper stays white in dark mode, so ink must keep its light-mode colours.
        canvas.overrideUserInterfaceStyle = .light
        addSubview(canvas)

        for view in [pagesView, desk] {
            view.layer.anchorPoint = .zero
            view.isUserInteractionEnabled = false
        }
        canvas.insertSubview(pagesView, at: 0)
        canvas.addSubview(desk)
        canvas.addInteraction(UIPencilInteraction(delegate: self))
        canvas.addGestureRecognizer(undoTap)
        canvas.addGestureRecognizer(eraserGesture)
        addSubview(eraserIndicator)

        updateDeskColor()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.updateDeskColor() }
        applyTool()
        applyInput()
        keyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepKeyboardAway() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    isolated deinit {
        inkSettling?.cancel()
        keyboardObserver.map(NotificationCenter.default.removeObserver)
    }

    /// The desk lies inside the canvas, which is always light, and has to follow the app's appearance itself.
    private func updateDeskColor() {
        desk.deskColor = Self.deskColor.resolvedColor(with: traitCollection)
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != viewportSize, bounds.width > 0, bounds.height > 0 else { return }

        let isFirstLayout = viewportSize == .zero
        let position = isFirstLayout ? nil : readingPosition()
        let zoomRelativeToFit = isFirstLayout ? 1 : canvas.zoomScale / fitZoom
        viewportSize = bounds.size
        canvas.frame = bounds

        applyLayout(zoom: fitZoom * zoomRelativeToFit)
        if let target = pendingScrollTarget {
            pendingScrollTarget = nil
            scroll(to: target, animated: false)
        } else if let position {
            restore(position)
        }
        settle()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateContentInset()
    }

    private var fitZoom: CGFloat { layout.zoom(fittingWidth: viewportSize.width) }

    private var pixelsPerPoint: CGFloat { canvas.zoomScale * traitCollection.displayScale }

    /// The viewport in document points.
    private var visibleRect: CGRect {
        let zoom = canvas.zoomScale
        return CGRect(
            x: canvas.contentOffset.x / zoom,
            y: canvas.contentOffset.y / zoom,
            width: viewportSize.width / zoom,
            height: viewportSize.height / zoom
        )
    }

    /// Sizes the content for the current page stack and re-applies the zoom, clamped to the limits
    /// that follow from the stack's width.
    private func applyLayout(zoom: CGFloat) {
        isApplyingLayout = true
        defer { isApplyingLayout = false }

        let fit = fitZoom
        let minimum = fit * ZoomLimit.minimumRelativeToFit
        let maximum = min(fit * ZoomLimit.maximumRelativeToFit, ZoomLimit.maximum)
        // The limits are widened first: a zoom outside the current limits would be clamped to them.
        canvas.minimumZoomScale = min(canvas.minimumZoomScale, minimum)
        canvas.maximumZoomScale = max(canvas.maximumZoomScale, maximum)
        canvas.zoomScale = min(max(zoom, minimum), maximum)
        canvas.minimumZoomScale = minimum
        canvas.maximumZoomScale = maximum
        canvas.contentSize = CGSize(
            width: layout.contentSize.width * canvas.zoomScale,
            height: layout.contentSize.height * canvas.zoomScale
        )
        pagesView.bounds = CGRect(origin: .zero, size: layout.contentSize)
        desk.bounds = pagesView.bounds
        applyZoomToPages()
        updateContentInset()
    }

    /// The canvas magnifies its ink itself; the views that share its document coordinates follow here.
    ///
    /// A zoom that went beyond its limit springs back once the fingers lift. The canvas then takes
    /// its final zoom at once and animates the view it magnifies there. Where UIKit does that inside
    /// an animation block, the pages and the desk are animated along with it; where it does not, they
    /// are given its animation. Otherwise they would show at the final zoom while the ink is still
    /// on its way.
    private func applyZoomToPages() {
        let scale = CGAffineTransform(scaleX: canvas.zoomScale, y: canvas.zoomScale)
        let springBack = zoomAnimation
        for view in [pagesView, desk] {
            view.layer.position = .zero
            view.transform = scale
            if let springBack, view.layer.animation(forKey: "transform") == nil {
                view.layer.add(springBack, forKey: "transform")
            }
        }
    }

    /// The animation with which the canvas brings the content it magnifies to its zoom, while it runs.
    private var zoomAnimation: CAAnimation? {
        canvas.subviews.lazy
            .filter { $0 !== self.pagesView && $0 !== self.desk }
            .compactMap { $0.layer.animation(forKey: "transform") }
            .first
    }

    /// Centres content that is smaller than the viewport and keeps the last page clear of
    /// the home indicator and the tool bar.
    private func updateContentInset() {
        let scale = traitCollection.displayScale
        let content = canvas.contentSize
        let horizontal = PixelGrid.snap(max(0, (viewportSize.width - content.width) / 2), pixelsPerPoint: scale)
        let vertical = PixelGrid.snap(max(0, (viewportSize.height - content.height) / 2), pixelsPerPoint: scale)
        let bottom = max(vertical, safeAreaInsets.bottom + Self.bottomClearance)
        let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: bottom, right: horizontal)
        if canvas.contentInset != inset {
            canvas.contentInset = inset
            canvas.verticalScrollIndicatorInsets.bottom = safeAreaInsets.bottom
        }
    }

    /// Brings the page backgrounds to full sharpness for the zoom the view has come to rest at.
    private func settle() {
        for (pageID, view) in pageViews {
            guard let index = indexByPageID[pageID] else { continue }
            place(view, atPageAt: index)
        }
        refresh()
    }

    /// Updates which pages have views and what each of them shows, for the current scroll position and zoom.
    private func refresh() {
        guard viewportSize != .zero, !isApplyingLayout else { return }
        let visible = visibleRect
        updateDisplayedPages(around: visible)

        // During a pinch the backgrounds keep their resolution; only pages that show nothing yet are rendered.
        let pixelsPerPagePoint = pixelsPerPoint * layout.scale
        for (pageID, view) in pageViews where !isZooming || view.isBlank {
            guard let index = indexByPageID[pageID] else { continue }
            view.update(
                visibleRect: visible.applying(layout.transform(ofPageAt: index).inverted()),
                pixelsPerPoint: pixelsPerPagePoint
            )
        }
        showDesk(around: visible)
        reportCurrentPage(in: visible)
        requestInk(around: visible)
        releaseDistantInk(isScrolling: isScrolling)
    }

    // MARK: Page views

    /// Pages this close to the viewport get a view; pages farther away give it up. Both in viewport
    /// heights. The distance between the two keeps a page from coming and going while the view moves
    /// back and forth, and a page's background from being rendered again.
    private enum PageReach {
        static let show: CGFloat = 0.5
        static let keep: CGFloat = 1.5
    }

    private func updateDisplayedPages(around visible: CGRect) {
        // While a zoom springs back, the canvas already reports where it will end; until then, more
        // of the notebook is in view.
        if zoomAnimation == nil {
            let kept = Set(layout.pageIndices(intersecting: visible.insetBy(dx: 0, dy: -visible.height * PageReach.keep)).map { pages[$0].id })
            for pageID in pageViews.keys where !kept.contains(pageID) {
                endDisplaying(pageID)
            }
        }
        for index in layout.pageIndices(intersecting: visible.insetBy(dx: 0, dy: -visible.height * PageReach.show))
        where pageViews[pages[index].id] == nil {
            display(pageAt: index)
        }
    }

    private func display(pageAt index: Int) {
        guard let delegate else { return }
        let page = pages[index]
        let view = reusablePageViews.popLast() ?? PageBackgroundView(renderPool: renderPool)
        view.display(pageSize: page.size.cgSize, renderer: delegate.backgroundRenderer(for: page))
        place(view, atPageAt: index)
        pagesView.addSubview(view)
        pageViews[page.id] = view
    }

    /// A page view keeps its bounds in page points and is magnified to its frame in the stack, with
    /// its corner on a screen pixel.
    private func place(_ view: PageBackgroundView, atPageAt index: Int) {
        let frame = layout.frame(ofPageAt: index)
        let origin = PixelGrid.snap(frame.origin, pixelsPerPoint: pixelsPerPoint)
        view.transform = CGAffineTransform(scaleX: layout.scale, y: layout.scale)
        view.center = CGPoint(x: origin.x + frame.width / 2, y: origin.y + frame.height / 2)
    }

    private func endDisplaying(_ pageID: Page.ID) {
        guard let view = pageViews.removeValue(forKey: pageID) else { return }
        view.removeFromSuperview()
        view.reset()
        reusablePageViews.append(view)
    }

    /// Covers what lies around the pages, a viewport further than can be seen: a zoom that springs
    /// back from beyond its limit comes to rest inside that.
    private func showDesk(around visible: CGRect) {
        let area = visible.insetBy(dx: -visible.width, dy: -visible.height)
        let shown = layout.pageIndices(intersecting: area).compactMap { pageViews[pages[$0].id]?.frame }
        desk.show(Desk.rects(around: shown, in: area))
    }

    private func reportCurrentPage(in visible: CGRect) {
        let index = layout.pageIndex(nearestTo: visible.midY)
        guard index != currentPageIndex else { return }
        currentPageIndex = index
        if let index {
            delegate?.canvasDidShowPage(at: index)
        }
    }

    // MARK: Reading position

    /// A place in the notebook that survives changes to the page stack, the zoom and the viewport.
    private struct ReadingPosition {
        let pageID: Page.ID
        /// From the top of the page to the top of the viewport, in document points.
        let offsetInPage: CGFloat
    }

    private func readingPosition() -> ReadingPosition? {
        let visible = visibleRect
        guard let index = layout.pageIndices(intersecting: visible).first ?? layout.pageIndex(nearestTo: visible.minY) else {
            return nil
        }
        return ReadingPosition(pageID: pages[index].id, offsetInPage: visible.minY - layout.frame(ofPageAt: index).minY)
    }

    private func restore(_ position: ReadingPosition) {
        var offset = canvas.contentOffset
        if let index = indexByPageID[position.pageID] {
            offset.y = (layout.frame(ofPageAt: index).minY + position.offsetInPage) * canvas.zoomScale
        }
        canvas.contentOffset = clamped(offset)
    }

    private func clamped(_ offset: CGPoint) -> CGPoint {
        let inset = canvas.contentInset
        let content = canvas.contentSize
        let maxX = max(-inset.left, content.width - viewportSize.width + inset.right)
        let maxY = max(-inset.top, content.height - viewportSize.height + inset.bottom)
        return CGPoint(x: min(max(offset.x, -inset.left), maxX), y: min(max(offset.y, -inset.top), maxY))
    }

    // MARK: Ink

    /// Replacing the ink under a tool would take the stroke away from it, and replacing it during
    /// a pinch would re-render what PencilKit is magnifying.
    private var canReplaceInk: Bool { !isToolInUse && inkSettling == nil && !isZooming }

    private func replaceInk(with strokes: [PKStroke]) {
        replaceInk(with: PKDrawing(strokes: strokes))
    }

    private func replaceInk(with drawing: PKDrawing) {
        isReplacingInk = true
        canvas.drawing = drawing
        isReplacingInk = false
        reportedInk = nil
        if tools.tool == .eraser {
            strokePoints.prepare(for: drawing.strokes)
        }
    }

    private func pageIDs(within reach: CGFloat, of visible: CGRect) -> [Page.ID] {
        layout.pageIndices(intersecting: visible.insetBy(dx: 0, dy: -visible.height * reach)).map { pageIDs[$0] }
    }

    private func holdsOrAwaitsInk(of pageID: Page.ID) -> Bool {
        inkRecord.contains(pageID) || inkRequests.contains(pageID) || arrivedInk[pageID] != nil
    }

    private func requestInk(around visible: CGRect) {
        for pageID in pageIDs(within: InkReach.load, of: visible) where !holdsOrAwaitsInk(of: pageID) {
            requestInk(of: pageID)
        }
    }

    private func requestInk(of pageID: Page.ID) {
        guard let delegate else { return }
        inkRequests.insert(pageID)
        Task { [weak self] in
            let strokes = await delegate.ink(for: pageID)
            self?.inkDidArrive(strokes, for: pageID)
        }
    }

    private func inkDidArrive(_ strokes: [PKStroke], for pageID: Page.ID) {
        // The request is gone when the page was removed in the meantime.
        guard inkRequests.remove(pageID) != nil, indexByPageID[pageID] != nil else { return }
        guard pageIDs(within: InkReach.keep, of: visibleRect).contains(pageID) else {
            delegate?.canvasDidEndDisplayingInk(of: pageID)
            return
        }
        arrivedInk[pageID] = strokes
        showArrivedInk()
    }

    /// Puts stored ink that has arrived into the canvas.
    ///
    /// The ink is added to what the canvas holds, which costs no more than the arriving ink itself.
    /// Only where a page was drawn on before its stored ink arrived is the ink of the canvas put
    /// together anew, with the stored ink beneath what was drawn.
    private func showArrivedInk() {
        guard canReplaceInk, !arrivedInk.isEmpty else { return }
        var arrived: [Int: [PKStroke]] = [:]
        var wasDrawnOn = false
        for (pageID, ink) in arrivedInk {
            guard let index = indexByPageID[pageID] else { continue }
            arrived[index] = ink
            inkRecord.set(ink, for: pageID)
            wasDrawnOn = pagesDrawnOnEarly.remove(pageID) != nil || wasDrawnOn
        }
        arrivedInk.removeAll()

        if wasDrawnOn {
            var strokes = canvas.drawing.strokes
            for (index, ink) in arrived {
                strokes = DocumentInk.strokes(strokes, adding: ink, beneathPageAt: index, layout: layout)
            }
            replaceInk(with: strokes)
            reportInkChanges()
            return
        }

        let placed = DocumentInk.strokes(joining: arrived, layout: layout)
        guard !placed.isEmpty else { return }
        let reported = reportedInk
        var drawing = canvas.drawing
        drawing.append(PKDrawing(strokes: placed))
        replaceInk(with: drawing)
        // The record took the arriving ink above and agrees with the canvas as it did before.
        reportedInk = reported.map { (count: $0.count + placed.count, lastID: placed.last?.id) }
    }

    private var isScrolling: Bool { canvas.isDragging || canvas.isDecelerating }

    /// Takes the ink of pages far from the viewport out of the canvas. It stays with the notebook.
    ///
    /// - Parameter isScrolling: While the view scrolls, pages wait until several of them can give
    ///   their ink up together.
    private func releaseDistantInk(isScrolling: Bool) {
        guard canReplaceInk, viewportSize != .zero else { return }
        let kept = Set(pageIDs(within: InkReach.keep, of: visibleRect))
        let leaving = inkRecord.pageIDs.subtracting(kept)
        guard !leaving.isEmpty, !isScrolling || leaving.count >= InkReach.pagesReleasedTogether else { return }

        // Ink that leaves the canvas unreported would be lost.
        if hasUnreportedInk {
            reportInkChanges()
        }
        let agrees = reportedInk != nil
        let strokes = canvas.drawing.strokes
        let remaining = DocumentInk.strokes(strokes, removingPagesAt: Set(leaving.compactMap { indexByPageID[$0] }), layout: layout)
        if remaining.count != strokes.count {
            replaceInk(with: remaining)
            reportedInk = agrees ? (remaining.count, remaining.last?.id) : nil
        }
        for pageID in leaving {
            inkRecord.remove(pageID)
            delegate?.canvasDidEndDisplayingInk(of: pageID)
        }
    }

    /// Waits for the ink to settle, then brings the canvas and the notebook up to date.
    private func settleInk() {
        inkSettling?.cancel()
        inkSettling = Task { [weak self] in
            try? await Task.sleep(for: Self.inkSettlingTime)
            guard !Task.isCancelled, let self else { return }
            self.inkSettling = nil
            self.inkDidSettle()
        }
    }

    private func inkDidSettle() {
        guard !isToolInUse else { return }
        if hasUnreportedInk {
            reportInkChanges()
        }
        showArrivedInk()
        releaseDistantInk(isScrolling: isScrolling)
        if hasErased {
            hasErased = false
            onEraseEnd?()
        }
    }

    /// The strokes that were drawn on top of the ink the record agrees with, or `nil` when more than
    /// that may have changed.
    private func strokesDrawn(onTopOfReportedInkIn strokes: [PKStroke]) -> [PKStroke]? {
        guard let reportedInk, strokes.count >= reportedInk.count else { return nil }
        if reportedInk.count > 0, strokes[reportedInk.count - 1].id != reportedInk.lastID { return nil }
        return Array(strokes[reportedInk.count...])
    }

    /// Splits what was drawn across the edge of a page into one stroke on each page and tells the
    /// notebook which pages' ink differs from what it was told last.
    ///
    /// After plain drawing, that takes a look at the new strokes only, and each of them, with all
    /// its parts, is a step of its own to undo. After anything else, all the ink of the canvas is
    /// compared with the record.
    private func reportInkChanges() {
        hasUnreportedInk = false
        var strokes = canvas.drawing.strokes
        if let drawn = strokesDrawn(onTopOfReportedInkIn: strokes) {
            guard !drawn.isEmpty else { return }
            let steps = drawn.map { DocumentInk.strokesSplitAtPages([$0], layout: layout) ?? [$0] }
            let parts = steps.flatMap { $0 }
            if parts.map(\.id) != drawn.map(\.id) {
                strokes.replaceSubrange((strokes.count - drawn.count)..., with: parts)
                replaceInk(with: strokes)
            }
            for step in steps where !step.isEmpty {
                tellNotebook(inkRecord.add(step, layout: layout, pageIDs: pageIDs))
            }
        } else {
            if let split = DocumentInk.strokesSplitAtPages(strokes, layout: layout) {
                strokes = split
                replaceInk(with: split)
            }
            tellNotebook(inkRecord.compare(with: strokes, layout: layout, pageIDs: pageIDs))
        }
        reportedInk = (strokes.count, strokes.last?.id)
    }

    private func tellNotebook(_ comparison: CanvasInk<Page.ID, PKStroke>.Comparison) {
        // A stroke can land on a page before its stored ink has. It is reported once both are there.
        pagesDrawnOnEarly.formUnion(comparison.pagesMissingInk)
        for pageID in comparison.pagesMissingInk where !holdsOrAwaitsInk(of: pageID) {
            requestInk(of: pageID)
        }
        if !comparison.changes.isEmpty {
            delegate?.canvasDidChangeInk(comparison.changes)
        }
    }

    /// Carries the ink along with its pages after the page stack changed.
    private func moveInk(from oldPageIDs: [Page.ID], in oldLayout: PageStackLayout) {
        var newIndices: [Int: Int] = [:]
        var keepsItsPlace = true
        for (oldIndex, pageID) in oldPageIDs.enumerated() {
            if let newIndex = indexByPageID[pageID] {
                newIndices[oldIndex] = newIndex
                keepsItsPlace = keepsItsPlace && layout.frame(ofPageAt: newIndex).origin == oldLayout.frame(ofPageAt: oldIndex).origin
            } else {
                inkRecord.remove(pageID)
                inkRequests.remove(pageID)
                arrivedInk[pageID] = nil
                pagesDrawnOnEarly.remove(pageID)
                keepsItsPlace = false
            }
        }
        let strokes = canvas.drawing.strokes
        guard !keepsItsPlace, !strokes.isEmpty else { return }
        replaceInk(with: DocumentInk.strokes(strokes, movedFrom: oldLayout, to: layout, newIndices: newIndices))
    }

    // MARK: Input

    /// Only Apple Pencil writes; fingers scroll and zoom. The Simulator has no Apple Pencil, so a
    /// finger or the pointer stands in for it there.
    private func applyInput() {
        #if targetEnvironment(simulator)
        canvas.drawingPolicy = .anyInput
        eraserGesture.allowedTouchTypes = [UITouch.TouchType.pencil, .direct].map { NSNumber(value: $0.rawValue) }
        #else
        canvas.drawingPolicy = .pencilOnly
        eraserGesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        #endif
    }

    private func applyTool() {
        if let tool = tools.pencilKitTool(documentScale: Self.documentScale) {
            canvas.tool = tool
        }
        let isErasing = tools.tool == .eraser
        canvas.drawingGestureRecognizer.isEnabled = !isErasing
        eraserGesture.isEnabled = isErasing
        if isErasing {
            strokePoints.prepare(for: canvas.drawing.strokes)
        }
        // A selection that the lasso leaves behind is put down when the tool changes.
        reportedInk = nil
        applySelectionGestures()
        eraserIndicator.hide()
    }

    // MARK: Erasing

    /// The eraser cuts what it touches out of the strokes, across their whole width, where PencilKit's
    /// erasers would take whole strokes or leave slivers of a line beside the eraser's path.
    private lazy var eraserGesture: EraserGestureRecognizer = {
        let gesture = EraserGestureRecognizer(target: self, action: #selector(followEraser(_:)))
        gesture.delegate = self
        return gesture
    }()

    /// Where the eraser was when it last erased, in document points.
    private var lastEraserLocation: CGPoint?
    /// The ink while the eraser is down. Nothing else changes the canvas's ink while a tool is in use.
    private var inkEraser: InkEraser?
    private let strokePoints = StrokePoints()

    @objc private func followEraser(_ gesture: EraserGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            if gesture.state == .began {
                isToolInUse = true
                inkSettling?.cancel()
                inkSettling = nil
                hasErased = true
                inkEraser = InkEraser(strokes: canvas.drawing.strokes, points: strokePoints)
                onToolBegin?()
            }
            eraserIndicator.show(at: gesture.location(in: self), diameter: tools.eraserDiameter)
            let location = gesture.location(in: pagesView)
            erase(from: lastEraserLocation ?? location, to: location)
            lastEraserLocation = location
        default:
            eraserIndicator.hide()
            lastEraserLocation = nil
            inkEraser = nil
            strokePoints.prepare(for: canvas.drawing.strokes)
            isToolInUse = false
            settleInk()
        }
    }

    /// Erases what the eraser swept over between two places in document points.
    private func erase(from start: CGPoint, to end: CGPoint) {
        let radius = tools.eraserDiameter / 2 / canvas.zoomScale
        guard inkEraser?.erase(from: start, to: end, radius: radius) == true, let strokes = inkEraser?.strokes else { return }
        reportedInk = nil
        canvas.drawing = PKDrawing(strokes: strokes)
    }

    /// PencilKit selects strokes and opens its edit menu on a tap or a long press, whatever the
    /// tool. Here that belongs to the lasso; with the other tools a resting hand must do nothing.
    private func applySelectionGestures() {
        let isSelecting = tools.tool == .lasso
        for recognizer in canvas.selectionGestureRecognizers {
            recognizer.isEnabled = isSelecting
        }
    }

    /// A double tap with two fingers undoes the last step.
    private lazy var undoTap: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(undoLastStep))
        tap.numberOfTouchesRequired = 2
        tap.numberOfTapsRequired = 2
        tap.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        return tap
    }()

    @objc private func undoLastStep() {
        undoManager?.undo()
    }

    override var canBecomeFirstResponder: Bool { true }

    override var undoManager: UndoManager? { delegate?.undoManager }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            reportPendingInk()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            becomeFirstResponder()
            applySelectionGestures()
        }
    }

    /// PencilKit takes the focus when strokes are selected and accepts typed text there, which
    /// brings a keyboard up over the pages. The focus returns to this view: the selection stays,
    /// and there is nothing to type.
    private func keepKeyboardAway() {
        if canvas.containsFirstResponder {
            becomeFirstResponder()
        }
    }
}

extension PagedCanvasView: PagedCanvasControlling {
    func setPages(_ newPages: [Page]) {
        guard newPages != pages else { return }
        let position = viewportSize == .zero ? nil : readingPosition()
        // What was drawn last is reported while the pages are still where it was drawn.
        reportPendingInk()
        let oldPageIDs = pageIDs
        let oldLayout = layout
        pages = newPages
        pageIDs = newPages.map(\.id)
        indexByPageID = Dictionary(uniqueKeysWithValues: zip(pageIDs, pageIDs.indices))
        layout = PageStackLayout(pageSizes: newPages.map(\.size.cgSize), scale: Self.documentScale)
        currentPageIndex = nil
        for pageID in pageViews.keys.filter({ indexByPageID[$0] == nil }) {
            endDisplaying(pageID)
        }
        moveInk(from: oldPageIDs, in: oldLayout)
        guard viewportSize != .zero else { return }

        applyLayout(zoom: canvas.zoomScale)
        if let position {
            restore(position)
        }
        settle()
    }

    func reportPendingInk() {
        guard hasUnreportedInk, !isToolInUse else { return }
        inkSettling?.cancel()
        inkSettling = nil
        inkDidSettle()
    }

    func setInk(_ strokes: [PKStroke], for pageID: Page.ID) {
        if arrivedInk[pageID] != nil {
            arrivedInk[pageID] = strokes
        }
        guard inkRecord.contains(pageID), let index = indexByPageID[pageID] else { return }
        let agrees = reportedInk != nil && !hasUnreportedInk
        let ink = DocumentInk.strokes(canvas.drawing.strokes, replacingPageAt: index, with: strokes, layout: layout)
        replaceInk(with: ink)
        inkRecord.set(strokes, for: pageID)
        reportedInk = agrees ? (ink.count, ink.last?.id) : nil
    }

    func scroll(to pageID: Page.ID, animated: Bool) {
        guard viewportSize != .zero, let index = indexByPageID[pageID] else {
            pendingScrollTarget = pageID
            return
        }
        let top = layout.frame(ofPageAt: index).minY - PageStackLayout.Metrics.standard.spacing * layout.scale / 2
        let target = clamped(CGPoint(x: canvas.contentOffset.x, y: top * canvas.zoomScale))
        canvas.setContentOffset(target, animated: animated)
    }

    func reveal(_ pageID: Page.ID) {
        guard let index = indexByPageID[pageID], !layout.frame(ofPageAt: index).intersects(visibleRect) else { return }
        scroll(to: pageID, animated: true)
    }
}

extension PagedCanvasView: PKCanvasViewDelegate {
    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        isToolInUse = true
        inkSettling?.cancel()
        inkSettling = nil
        onToolBegin?()
    }


    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        isToolInUse = false
        settleInk()
    }

    /// The ink is not looked at here. An eraser or a lasso changes it many times while it moves,
    /// and what it did is one step to undo; a stroke may have to be split at the edge of its page
    /// before it is reported; and while the writing goes on, nothing is to hold it up.
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isReplacingInk else { return }
        // Only the pen leaves the ink beneath its strokes as it was.
        if !(canvasView.tool is PKInkingTool) {
            reportedInk = nil
        }
        hasUnreportedInk = true
        if !isToolInUse {
            settleInk()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        refresh()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            releaseDistantInk(isScrolling: false)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        releaseDistantInk(isScrolling: false)
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        isZooming = true
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard !isApplyingLayout else { return }
        applyZoomToPages()
        updateContentInset()
        refresh()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        isZooming = false
        settle()
        showArrivedInk()
    }
}

extension PagedCanvasView: UIPencilInteractionDelegate {
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        switch UIPencilInteraction.preferredTapAction {
        case .switchEraser: onPencilShortcut?(.toggleEraser)
        case .switchPrevious: onPencilShortcut?(.selectPreviousTool)
        case .showColorPalette, .showInkAttributes, .showContextualPalette: onPencilShortcut?(.toggleOptions)
        default: break
        }
    }
}

/// The PencilKit canvas of a notebook.
private final class InkCanvasView: PKCanvasView {
    var notebookUndoManager: UndoManager?

    /// PencilKit records its undo steps in the manager it finds here. The notebook's manager records
    /// nothing and passes undoing on to the notebook's own history.
    override var undoManager: UndoManager? { notebookUndoManager }

    /// Whether the canvas or one of the views PencilKit keeps in it has the focus.
    var containsFirstResponder: Bool {
        func hasFocus(_ view: UIView) -> Bool {
            view.isFirstResponder || view.subviews.contains(where: hasFocus)
        }
        return hasFocus(self)
    }

    /// The taps and long presses with which PencilKit selects strokes and opens its edit menu.
    ///
    /// They are found by what they are, not by name: tap and long-press recognizers on the views
    /// that PencilKit itself puts into the canvas.
    var selectionGestureRecognizers: [UIGestureRecognizer] {
        let pencilKit = Bundle(for: PKCanvasView.self)
        func recognizers(in view: UIView) -> [UIGestureRecognizer] {
            let own = Bundle(for: type(of: view)) == pencilKit ? view.gestureRecognizers ?? [] : []
            return own + view.subviews.flatMap(recognizers)
        }
        return subviews.flatMap(recognizers).filter { recognizer in
            recognizer !== drawingGestureRecognizer
                && (recognizer is UITapGestureRecognizer || recognizer is UILongPressGestureRecognizer)
        }
    }
}

extension PagedCanvasView: UIGestureRecognizerDelegate {
    /// The eraser lets the canvas scroll and zoom, so that a second finger can take over from it.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === eraserGesture && (other === canvas.panGestureRecognizer || other === canvas.pinchGestureRecognizer)
    }
}
