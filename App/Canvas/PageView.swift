import LinedLayout
import LinedModel
import LinedRendering
import PencilKit
import UIKit

/// One page on screen: its background with the ink canvas on top.
///
/// The view's bounds are the page in page points. The enclosing scroll view magnifies it; the canvas
/// undoes that magnification with its own transform and renders at its own zoom instead, which keeps
/// ink as sharp as the screen allows.
final class PageView: UIView {
    let canvas = InkCanvasView()
    var onDrawingChange: ((Page.ID, PKDrawing) -> Void)?

    private(set) var pageID: Page.ID?
    private let background: PageBackgroundView
    private var pageSize = CGSize.zero
    private var inkWindow: InkWindow?
    private var isShowingDrawing = false

    init(renderPool: BackgroundRenderPool) {
        background = PageBackgroundView(renderPool: renderPool)
        super.init(frame: .zero)
        clipsToBounds = true
        layer.borderColor = UIColor(white: 0, alpha: 0.14).cgColor
        layer.borderWidth = 0.5
        background.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(background)
        addSubview(canvas)
        canvas.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows the page without ink. The canvas accepts input once `show(_:)` has delivered the stored
    /// drawing, so that strokes cannot land on a page whose ink is still loading.
    func display(_ page: Page, background renderer: any PageBackgroundRenderer) {
        pageID = page.id
        pageSize = page.size.cgSize
        bounds = CGRect(origin: .zero, size: pageSize)
        background.display(pageSize: pageSize, renderer: renderer)
        inkWindow = nil
    }

    func show(_ drawing: PKDrawing) {
        isShowingDrawing = true
        canvas.drawing = drawing
        isShowingDrawing = false
        canvas.isUserInteractionEnabled = true
    }

    func prepareForReuse() {
        pageID = nil
        canvas.isUserInteractionEnabled = false
        isShowingDrawing = true
        canvas.drawing = PKDrawing()
        isShowingDrawing = false
        background.reset()
    }

    /// Places the canvas over the visible part of the page.
    ///
    /// - Parameters:
    ///   - visibleRect: The viewport in page points.
    ///   - viewZoom: The magnification the page is shown at.
    func layoutInk(visibleRect: CGRect, viewportSize: CGSize, viewZoom: CGFloat, isZoomSettled: Bool) {
        let zoom = isZoomSettled ? viewZoom : InkWindow.zoom(whileZoomingFrom: inkWindow?.zoom ?? viewZoom, viewZoom: viewZoom)
        let window = InkWindow(pageSize: pageSize, visibleRect: visibleRect, viewportSize: viewportSize, zoom: zoom)
        guard window != inkWindow else { return }
        if window.zoom != inkWindow?.zoom {
            canvas.setZoom(zoom, pageSize: pageSize)
            canvas.transform = CGAffineTransform(scaleX: 1 / zoom, y: 1 / zoom)
        }
        canvas.bounds = CGRect(
            origin: CGPoint(x: window.origin.x * zoom, y: window.origin.y * zoom),
            size: window.canvasSize
        )
        canvas.center = CGPoint(x: window.pageRect.midX, y: window.pageRect.midY)
        inkWindow = window
    }

    func renderBackground(visibleRect: CGRect, pixelsPerPoint: CGFloat) {
        background.update(visibleRect: visibleRect, pixelsPerPoint: pixelsPerPoint)
    }

    /// Gives up the rendered images of a page that is kept far from the viewport. The next
    /// `layoutInk` and `renderBackground` bring them back.
    func suspend() {
        guard inkWindow != nil else { return }
        inkWindow = nil
        canvas.bounds.size = .zero
        background.releaseImages()
    }
}

extension PageView: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isShowingDrawing, let pageID else { return }
        onDrawingChange?(pageID, canvasView.drawing)
    }
}

/// A PencilKit canvas that leaves scrolling and zooming to the notebook view around it.
final class InkCanvasView: PKCanvasView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isScrollEnabled = false
        scrollsToTop = false
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        pinchGestureRecognizer?.isEnabled = false
        isUserInteractionEnabled = false
        // Paper stays white in dark mode, so ink must keep its light-mode colours.
        overrideUserInterfaceStyle = .light
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setZoom(_ zoom: CGFloat, pageSize: CGSize) {
        minimumZoomScale = min(minimumZoomScale, zoom)
        maximumZoomScale = max(maximumZoomScale, zoom)
        zoomScale = zoom
        minimumZoomScale = zoom
        maximumZoomScale = zoom
        contentSize = CGSize(width: pageSize.width * zoom, height: pageSize.height * zoom)
    }
}
