import CoreGraphics

/// The part of a page that the page's ink canvas covers.
///
/// A canvas renders its whole bounds at its own zoom, so a canvas as large as a magnified page would cost
/// memory in proportion to the zoom squared. The canvas is therefore never larger than the viewport and
/// slides over the page instead, following the visible part.
public struct InkWindow: Equatable, Sendable {
    /// The window's top-left corner in page points.
    public let origin: CGPoint
    /// The canvas size in its own points, which are screen points at the canvas zoom.
    public let canvasSize: CGSize
    public let zoom: CGFloat

    /// - Parameters:
    ///   - visibleRect: The viewport in page points; may lie partly or entirely outside the page.
    ///   - zoom: The canvas zoom. The window covers the visible part of the page as long as this
    ///     does not exceed the zoom the page is shown at.
    public init(pageSize: CGSize, visibleRect: CGRect, viewportSize: CGSize, zoom: CGFloat) {
        let canvasSize = CGSize(
            width: min(viewportSize.width, pageSize.width * zoom),
            height: min(viewportSize.height, pageSize.height * zoom)
        )
        self.canvasSize = canvasSize
        self.zoom = zoom
        origin = CGPoint(
            x: min(max(visibleRect.minX, 0), pageSize.width - canvasSize.width / zoom),
            y: min(max(visibleRect.minY, 0), pageSize.height - canvasSize.height / zoom)
        )
    }

    /// The covered part of the page in page points.
    public var pageRect: CGRect {
        CGRect(origin: origin, size: CGSize(width: canvasSize.width / zoom, height: canvasSize.height / zoom))
    }

    /// The zoom a canvas should use while the page is shown at `viewZoom` and the zoom is still changing.
    ///
    /// The canvas keeps its zoom while the view zooms in, which only magnifies what it already rendered.
    /// Zooming out past the canvas zoom would uncover page area outside the window, so the canvas drops
    /// below the view zoom with some headroom, rather than re-rendering on every step of the gesture.
    public static func zoom(whileZoomingFrom canvasZoom: CGFloat, viewZoom: CGFloat) -> CGFloat {
        viewZoom < canvasZoom ? viewZoom * 0.7 : canvasZoom
    }
}
