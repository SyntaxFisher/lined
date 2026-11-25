import LinedLayout
import LinedModel
import LinedRendering
import PencilKit
import UIKit

/// What a paged canvas needs from, and reports to, the notebook it shows.
protocol PagedCanvasDelegate: AnyObject {
    /// The notebook's undo history, which the canvases record their steps in.
    var undoManager: UndoManager { get }
    /// The canvas dropped the undo steps of a page it no longer displays.
    func canvasDidChangeUndoHistory()
    func backgroundRenderer(for page: Page) -> any PageBackgroundRenderer
    func drawing(for pageID: Page.ID) async -> PKDrawing
    func canvasDidChangeDrawing(_ drawing: PKDrawing, on pageID: Page.ID)
    func canvasDidEndDisplayingPage(_ pageID: Page.ID)
    func canvasDidShowPage(at index: Int)
}

/// The commands a notebook sends to the canvas that shows it.
protocol PagedCanvasControlling: AnyObject {
    func setPages(_ pages: [Page])
    func scroll(to pageID: Page.ID, animated: Bool)
    /// Scrolls to the page unless part of it is already in view.
    func reveal(_ pageID: Page.ID)
}

/// Scrolls and zooms the pages of a notebook as one continuous vertical stack.
///
/// A single scroll view owns scrolling and zooming and magnifies a content view laid out in page points.
/// Only the pages near the viewport have views, so memory and work do not grow with the page count.
///
/// Undo steps belong to the canvas that recorded them. The pages edited last therefore keep their views
/// while out of sight, and a page that loses its view loses its undo steps with it.
final class PagedCanvasView: UIView {
    weak var delegate: (any PagedCanvasDelegate)?

    var allowsFingerDrawing = false {
        didSet {
            if allowsFingerDrawing != oldValue { applyDrawingPolicy() }
        }
    }

    var isToolPickerVisible = false {
        didSet {
            if isToolPickerVisible != oldValue { applyToolPickerVisibility() }
        }
    }

    private enum ZoomLimit {
        static let minimumRelativeToFit: CGFloat = 0.5
        static let maximumRelativeToFit: CGFloat = 8
    }

    /// How many edited pages keep their view, and with it their undo steps, while out of sight.
    private static let undoablePageLimit = 8

    private let scrollView = UIScrollView()
    private let twoFingerObserver = TwoFingerObserver()
    private let contentView = UIView()
    private let toolPicker = PKToolPicker()
    private let renderPool = BackgroundRenderPool()

    private var pages: [Page] = []
    private var indexByPageID: [Page.ID: Int] = [:]
    private var layout = PageStackLayout(pageSizes: [])
    private var pageViews: [Page.ID: PageView] = [:]
    /// The pages edited last, most recent at the end.
    private var recentlyEditedPages: [Page.ID] = []
    private var reusablePageViews: [PageView] = []
    private var viewportSize = CGSize.zero
    private var isZooming = false
    private var isApplyingLayout = false
    private var currentPageIndex: Int?
    private var pendingScrollTarget: Page.ID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        // Apple Pencil draws; only fingers scroll.
        scrollView.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        twoFingerObserver.onChange = { [weak self] areDown in self?.areTwoFingersDown = areDown }
        scrollView.addGestureRecognizer(twoFingerObserver)
        scrollView.addSubview(contentView)
        addSubview(scrollView)
        toolPicker.colorUserInterfaceStyle = .light
        toolPicker.addObserver(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        guard bounds.size != viewportSize, bounds.width > 0, bounds.height > 0 else { return }

        let isFirstLayout = viewportSize == .zero
        let position = isFirstLayout ? nil : readingPosition()
        let zoomRelativeToFit = isFirstLayout ? 1 : scrollView.zoomScale / fitZoom
        viewportSize = bounds.size

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

    private var pixelsPerPoint: CGFloat { scrollView.zoomScale * traitCollection.displayScale }

    /// The viewport in document points.
    private var visibleRect: CGRect {
        let zoom = scrollView.zoomScale
        return CGRect(
            x: scrollView.contentOffset.x / zoom,
            y: scrollView.contentOffset.y / zoom,
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
        scrollView.minimumZoomScale = fit * ZoomLimit.minimumRelativeToFit
        scrollView.maximumZoomScale = fit * ZoomLimit.maximumRelativeToFit
        contentView.transform = .identity
        contentView.frame = CGRect(origin: .zero, size: layout.contentSize)
        scrollView.contentSize = layout.contentSize
        scrollView.zoomScale = min(max(zoom, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        updateContentInset()
    }

    /// Centres content that is smaller than the viewport and keeps the last page clear of
    /// the home indicator and a docked tool picker.
    private func updateContentInset() {
        let scale = traitCollection.displayScale
        let content = scrollView.contentSize
        let horizontal = PixelGrid.snap(max(0, (viewportSize.width - content.width) / 2), pixelsPerPoint: scale)
        let vertical = PixelGrid.snap(max(0, (viewportSize.height - content.height) / 2), pixelsPerPoint: scale)
        let obscured = toolPicker.frameObscured(in: self)
        let bottom = max(vertical, safeAreaInsets.bottom, obscured.isNull ? 0 : bounds.maxY - obscured.minY)
        let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: bottom, right: horizontal)
        if scrollView.contentInset != inset {
            scrollView.contentInset = inset
            scrollView.verticalScrollIndicatorInsets.bottom = bottom
        }
    }

    /// Brings the displayed pages to full sharpness for the zoom the view has come to rest at.
    private func settle() {
        let pixelsPerPoint = pixelsPerPoint
        for (pageID, view) in pageViews {
            guard let index = indexByPageID[pageID] else { continue }
            view.frame.origin = PixelGrid.snap(layout.frame(ofPageAt: index).origin, pixelsPerPoint: pixelsPerPoint)
        }
        let offset = PixelGrid.snap(scrollView.contentOffset, pixelsPerPoint: traitCollection.displayScale)
        if offset != scrollView.contentOffset {
            scrollView.contentOffset = offset
        }
        refresh()
    }

    /// Updates which pages have views and what each of them shows, for the current scroll position and zoom.
    private func refresh() {
        guard viewportSize != .zero, !isApplyingLayout else { return }
        let visible = visibleRect
        updateDisplayedPages(around: visible)

        let reach = reach(around: visible)
        let zoom = scrollView.zoomScale
        let pixelsPerPoint = pixelsPerPoint
        for view in pageViews.values {
            guard view.frame.maxY > reach.minY, view.frame.minY < reach.maxY else {
                view.suspend()
                continue
            }
            let visibleInPage = visible.offsetBy(dx: -view.frame.minX, dy: -view.frame.minY)
            view.layoutInk(visibleRect: visibleInPage, viewportSize: viewportSize, viewZoom: zoom, isZoomSettled: !isZooming)
            if !isZooming {
                view.renderBackground(visibleRect: visibleInPage, pixelsPerPoint: pixelsPerPoint)
            }
        }
        reportCurrentPage(in: visible)
    }

    // MARK: Page views

    /// The viewport extended by half its height in both directions: the pages to keep ready.
    private func reach(around visible: CGRect) -> CGRect {
        visible.insetBy(dx: 0, dy: -visible.height / 2)
    }

    private func updateDisplayedPages(around visible: CGRect) {
        let nearby = layout.pageIndices(intersecting: reach(around: visible))
        let wanted = Set(nearby.map { pages[$0].id }).union(recentlyEditedPages)
        for pageID in pageViews.keys.filter({ !wanted.contains($0) }) {
            endDisplaying(pageID)
        }
        for index in nearby where pageViews[pages[index].id] == nil {
            display(pageAt: index)
        }
    }

    private func display(pageAt index: Int) {
        guard let delegate else { return }
        let page = pages[index]
        let view = reusablePageViews.popLast() ?? makePageView()
        view.display(page, background: delegate.backgroundRenderer(for: page))
        view.frame.origin = PixelGrid.snap(layout.frame(ofPageAt: index).origin, pixelsPerPoint: pixelsPerPoint)
        applyDrawingPolicy(to: view)
        contentView.addSubview(view)
        pageViews[page.id] = view
        toolPicker.addObserver(view.canvas)

        Task { [weak self, weak view] in
            guard let drawing = await self?.delegate?.drawing(for: page.id), let view, view.pageID == page.id else { return }
            view.show(drawing)
        }
    }

    private func endDisplaying(_ pageID: Page.ID) {
        guard let view = pageViews.removeValue(forKey: pageID) else { return }
        if view.canvas.isFirstResponder, isToolPickerVisible {
            becomeFirstResponder()
        }
        toolPicker.removeObserver(view.canvas)
        forgetUndoSteps(recordedBy: view.canvas)
        view.removeFromSuperview()
        view.prepareForReuse()
        reusablePageViews.append(view)
        recentlyEditedPages.removeAll { $0 == pageID }
        delegate?.canvasDidEndDisplayingPage(pageID)
        delegate?.canvasDidChangeUndoHistory()
    }

    /// PencilKit registers its undo steps with views inside the canvas. They must go before the canvas
    /// shows another page, where they would apply to the wrong ink.
    private func forgetUndoSteps(recordedBy view: UIView) {
        undoManager?.removeAllActions(withTarget: view)
        view.subviews.forEach(forgetUndoSteps)
    }

    private func makePageView() -> PageView {
        let view = PageView(renderPool: renderPool)
        view.onDrawingChange = { [weak self] pageID, drawing in
            self?.noteEdit(of: pageID)
            self?.delegate?.canvasDidChangeDrawing(drawing, on: pageID)
        }
        return view
    }

    private func noteEdit(of pageID: Page.ID) {
        recentlyEditedPages.removeAll { $0 == pageID }
        recentlyEditedPages.append(pageID)
        if recentlyEditedPages.count > Self.undoablePageLimit {
            recentlyEditedPages.removeFirst()
        }
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
        var offset = scrollView.contentOffset
        if let index = indexByPageID[position.pageID] {
            offset.y = (layout.frame(ofPageAt: index).minY + position.offsetInPage) * scrollView.zoomScale
        }
        scrollView.contentOffset = clamped(offset)
    }

    private func clamped(_ offset: CGPoint) -> CGPoint {
        let inset = scrollView.contentInset
        let content = scrollView.contentSize
        let maxX = max(-inset.left, content.width - viewportSize.width + inset.right)
        let maxY = max(-inset.top, content.height - viewportSize.height + inset.bottom)
        return CGPoint(x: min(max(offset.x, -inset.left), maxX), y: min(max(offset.y, -inset.top), maxY))
    }

    // MARK: Input

    /// Two fingers scroll and zoom. Each may land on a different page, where its canvas would take the
    /// single finger for a stroke and keep the scroll view waiting, so no canvas draws meanwhile.
    private var areTwoFingersDown = false {
        didSet {
            if areTwoFingersDown != oldValue { applyDrawingPolicy() }
        }
    }

    private func applyDrawingPolicy() {
        // With finger drawing, one finger writes and two fingers scroll.
        scrollView.panGestureRecognizer.minimumNumberOfTouches = allowsFingerDrawing ? 2 : 1
        pageViews.values.forEach(applyDrawingPolicy)
    }

    private func applyDrawingPolicy(to view: PageView) {
        view.canvas.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        view.canvas.drawingGestureRecognizer.isEnabled = !(allowsFingerDrawing && areTwoFingersDown)
    }

    override var canBecomeFirstResponder: Bool { true }

    /// Reached by every canvas through the responder chain, so that all pages share one history and
    /// the tool picker's undo buttons, the undo gestures and the keyboard act on it.
    override var undoManager: UndoManager? { delegate?.undoManager }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyToolPickerVisibility()
    }

    /// The canvases inherit the tool picker from this view through the responder chain.
    private func applyToolPickerVisibility() {
        pencilKitResponderState.activeToolPicker = toolPicker
        pencilKitResponderState.toolPickerVisibility = isToolPickerVisible ? .visible : .hidden
        if isToolPickerVisible, window != nil, !pageViews.values.contains(where: \.canvas.isFirstResponder) {
            becomeFirstResponder()
        }
    }
}

extension PagedCanvasView: PagedCanvasControlling {
    func setPages(_ newPages: [Page]) {
        guard newPages != pages else { return }
        let position = viewportSize == .zero ? nil : readingPosition()
        pages = newPages
        indexByPageID = Dictionary(uniqueKeysWithValues: newPages.enumerated().map { ($1.id, $0) })
        layout = PageStackLayout(pageSizes: newPages.map(\.size.cgSize))
        currentPageIndex = nil
        recentlyEditedPages.removeAll { indexByPageID[$0] == nil }
        for pageID in pageViews.keys.filter({ indexByPageID[$0] == nil }) {
            endDisplaying(pageID)
        }
        guard viewportSize != .zero else { return }

        applyLayout(zoom: scrollView.zoomScale)
        if let position {
            restore(position)
        }
        settle()
    }

    func scroll(to pageID: Page.ID, animated: Bool) {
        guard viewportSize != .zero, let index = indexByPageID[pageID] else {
            pendingScrollTarget = pageID
            return
        }
        let top = layout.frame(ofPageAt: index).minY - PageStackLayout.Metrics.standard.spacing / 2
        let target = clamped(CGPoint(x: scrollView.contentOffset.x, y: top * scrollView.zoomScale))
        scrollView.setContentOffset(target, animated: animated)
    }

    func reveal(_ pageID: Page.ID) {
        guard let index = indexByPageID[pageID], !layout.frame(ofPageAt: index).intersects(visibleRect) else { return }
        scroll(to: pageID, animated: true)
    }
}

extension PagedCanvasView: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        refresh()
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        isZooming = true
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard !isApplyingLayout else { return }
        updateContentInset()
        refresh()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        isZooming = false
        settle()
    }
}

extension PagedCanvasView: PKToolPickerObserver {
    func toolPickerFramesObscuredDidChange(_ toolPicker: PKToolPicker) {
        updateContentInset()
    }

    func toolPickerVisibilityDidChange(_ toolPicker: PKToolPicker) {
        updateContentInset()
    }
}
