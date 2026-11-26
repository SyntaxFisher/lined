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

    var allowsFingerDrawing = false {
        didSet {
            if allowsFingerDrawing != oldValue { applyInput() }
        }
    }

    var tools = ToolSettings() {
        didSet {
            if tools != oldValue { applyTool() }
        }
    }

    private enum ZoomLimit {
        static let minimumRelativeToFit: CGFloat = 0.5
        static let maximumRelativeToFit: CGFloat = 5
    }

    /// How far around the viewport the canvas holds ink, in viewport heights.
    private enum InkReach {
        /// Pages this close have their ink loaded before they scroll into view.
        static let load: CGFloat = 1.5
        /// Pages farther away give their ink up. The distance to `load` keeps a page from loading
        /// and unloading while the view moves back and forth.
        static let keep: CGFloat = 3
    }

    /// Room below the last page, so that its end can be scrolled clear of a tool bar docked at the bottom.
    private static let bottomClearance: CGFloat = 96

    private static let deskColor = UIColor.secondarySystemBackground

    private let canvas = InkCanvasView()
    /// Holds the page backgrounds beneath the ink, laid out in document points.
    private let pagesView = UIView()
    private let deskMask = DeskMaskView()
    private let renderPool = BackgroundRenderPool()

    private var pages: [Page] = []
    private var pageIDs: [Page.ID] = []
    private var indexByPageID: [Page.ID: Int] = [:]
    private var layout = PageStackLayout(pageSizes: [])
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
    private var isToolInUse = false
    private var hasUnreportedInk = false
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

        for view in [pagesView, deskMask] {
            view.layer.anchorPoint = .zero
            view.isUserInteractionEnabled = false
        }
        canvas.insertSubview(pagesView, at: 0)
        canvas.addSubview(deskMask)
        canvas.addInteraction(UIPencilInteraction(delegate: self))

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
        keyboardObserver.map(NotificationCenter.default.removeObserver)
    }

    /// The mask lives inside the canvas, which is always light, and has to follow the app's appearance itself.
    private func updateDeskColor() {
        deskMask.deskColor = Self.deskColor.resolvedColor(with: traitCollection)
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
        let maximum = fit * ZoomLimit.maximumRelativeToFit
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
        deskMask.bounds = pagesView.bounds
        applyZoomToPages()
        updateContentInset()
    }

    /// The canvas magnifies its ink itself; the views that share its document coordinates follow here.
    private func applyZoomToPages() {
        let scale = CGAffineTransform(scaleX: canvas.zoomScale, y: canvas.zoomScale)
        for view in [pagesView, deskMask] {
            view.layer.position = .zero
            view.transform = scale
        }
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
        let pixelsPerPoint = pixelsPerPoint
        for (pageID, view) in pageViews {
            guard let index = indexByPageID[pageID] else { continue }
            view.frame.origin = PixelGrid.snap(layout.frame(ofPageAt: index).origin, pixelsPerPoint: pixelsPerPoint)
        }
        refresh()
    }

    /// Updates which pages have views and what each of them shows, for the current scroll position and zoom.
    private func refresh() {
        guard viewportSize != .zero, !isApplyingLayout else { return }
        let visible = visibleRect
        let reach = reach(around: visible)
        updateDisplayedPages(within: reach)

        // During a pinch the backgrounds keep their resolution; only pages that show nothing yet are rendered.
        let pixelsPerPoint = pixelsPerPoint
        for view in pageViews.values where !isZooming || view.isBlank {
            view.update(
                visibleRect: visible.offsetBy(dx: -view.frame.minX, dy: -view.frame.minY),
                pixelsPerPoint: pixelsPerPoint
            )
        }
        let shown = layout.pageIndices(intersecting: reach).map(layout.frame(ofPageAt:))
        deskMask.uncover(shown, within: reach.union(CGRect(origin: .zero, size: layout.contentSize)).insetBy(dx: -reach.width, dy: -reach.height))
        reportCurrentPage(in: visible)
        requestInk(around: visible)
        releaseDistantInk()
    }

    // MARK: Page views

    /// The viewport extended by half its height in both directions: the pages to keep ready.
    private func reach(around visible: CGRect) -> CGRect {
        visible.insetBy(dx: 0, dy: -visible.height / 2)
    }

    private func updateDisplayedPages(within reach: CGRect) {
        let nearby = layout.pageIndices(intersecting: reach)
        let wanted = Set(nearby.map { pages[$0].id })
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
        let view = reusablePageViews.popLast() ?? PageBackgroundView(renderPool: renderPool)
        view.display(pageSize: page.size.cgSize, renderer: delegate.backgroundRenderer(for: page))
        view.frame.origin = PixelGrid.snap(layout.frame(ofPageAt: index).origin, pixelsPerPoint: pixelsPerPoint)
        pagesView.addSubview(view)
        pageViews[page.id] = view
    }

    private func endDisplaying(_ pageID: Page.ID) {
        guard let view = pageViews.removeValue(forKey: pageID) else { return }
        view.removeFromSuperview()
        view.reset()
        reusablePageViews.append(view)
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
    private var canReplaceInk: Bool { !isToolInUse && !isZooming }

    private func replaceInk(with strokes: [PKStroke]) {
        isReplacingInk = true
        canvas.drawing = PKDrawing(strokes: strokes)
        isReplacingInk = false
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
        guard inkRequests.remove(pageID) != nil else { return }
        guard pageIDs(within: InkReach.keep, of: visibleRect).contains(pageID) else {
            delegate?.canvasDidEndDisplayingInk(of: pageID)
            return
        }
        arrivedInk[pageID] = strokes
        showArrivedInk()
    }

    /// Puts stored ink that has arrived into the canvas, beneath what was drawn on its page meanwhile.
    private func showArrivedInk() {
        guard canReplaceInk, !arrivedInk.isEmpty else { return }
        var strokes = canvas.drawing.strokes
        let countBefore = strokes.count
        for (pageID, ink) in arrivedInk {
            guard let index = indexByPageID[pageID] else { continue }
            strokes = DocumentInk.strokes(strokes, adding: ink, beneathPageAt: index, layout: layout)
            inkRecord.set(ink, for: pageID)
        }
        arrivedInk.removeAll()
        if strokes.count != countBefore {
            replaceInk(with: strokes)
        }
        reportInkChanges()
    }

    /// Takes the ink of pages far from the viewport out of the canvas. It stays with the notebook.
    private func releaseDistantInk() {
        guard canReplaceInk, viewportSize != .zero else { return }
        let kept = Set(pageIDs(within: InkReach.keep, of: visibleRect))
        let leaving = inkRecord.pageIDs.subtracting(kept)
        guard !leaving.isEmpty else { return }

        reportInkChanges()
        let strokes = canvas.drawing.strokes
        let remaining = DocumentInk.strokes(strokes, removingPagesAt: Set(leaving.compactMap { indexByPageID[$0] }), layout: layout)
        if remaining.count != strokes.count {
            replaceInk(with: remaining)
        }
        for pageID in leaving {
            inkRecord.remove(pageID)
            delegate?.canvasDidEndDisplayingInk(of: pageID)
        }
    }

    /// Tells the notebook which pages' ink differs from what it was told last.
    private func reportInkChanges() {
        hasUnreportedInk = false
        let comparison = inkRecord.compare(with: canvas.drawing.strokes, layout: layout, pageIDs: pageIDs)
        // A stroke can land on a page before its stored ink has. It is reported once both are there.
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
                keepsItsPlace = false
            }
        }
        let strokes = canvas.drawing.strokes
        guard !keepsItsPlace, !strokes.isEmpty else { return }
        replaceInk(with: DocumentInk.strokes(strokes, movedFrom: oldLayout, to: layout, newIndices: newIndices))
    }

    // MARK: Input

    private func applyInput() {
        canvas.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
    }

    private func applyTool() {
        canvas.tool = tools.pencilKitTool
        applySelectionGestures()
    }

    /// PencilKit selects strokes and opens its edit menu on a tap or a long press, whatever the
    /// tool. Here that belongs to the lasso; with the other tools a resting hand must do nothing.
    private func applySelectionGestures() {
        let isSelecting = tools.tool == .lasso
        for recognizer in canvas.selectionGestureRecognizers {
            recognizer.isEnabled = isSelecting
        }
    }

    override var canBecomeFirstResponder: Bool { true }

    override var undoManager: UndoManager? { delegate?.undoManager }

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
        reportInkChanges()
        let oldPageIDs = pageIDs
        let oldLayout = layout
        pages = newPages
        pageIDs = newPages.map(\.id)
        indexByPageID = Dictionary(uniqueKeysWithValues: zip(pageIDs, pageIDs.indices))
        layout = PageStackLayout(pageSizes: newPages.map(\.size.cgSize))
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

    func setInk(_ strokes: [PKStroke], for pageID: Page.ID) {
        if arrivedInk[pageID] != nil {
            arrivedInk[pageID] = strokes
        }
        guard inkRecord.contains(pageID), let index = indexByPageID[pageID] else { return }
        replaceInk(with: DocumentInk.strokes(canvas.drawing.strokes, replacingPageAt: index, with: strokes, layout: layout))
        inkRecord.set(strokes, for: pageID)
    }

    func scroll(to pageID: Page.ID, animated: Bool) {
        guard viewportSize != .zero, let index = indexByPageID[pageID] else {
            pendingScrollTarget = pageID
            return
        }
        let top = layout.frame(ofPageAt: index).minY - PageStackLayout.Metrics.standard.spacing / 2
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
        onToolBegin?()
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        isToolInUse = false
        if hasUnreportedInk {
            reportInkChanges()
        }
        showArrivedInk()
        releaseDistantInk()
        if canvasView.tool is PKEraserTool {
            onEraseEnd?()
        }
    }

    /// An eraser or a lasso changes the ink many times while it moves. What it did is reported once,
    /// when it lifts, so that it is one step to undo.
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isReplacingInk else { return }
        if isToolInUse {
            hasUnreportedInk = true
        } else {
            reportInkChanges()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        refresh()
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
