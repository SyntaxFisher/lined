import CoreGraphics

/// A bitmap to render: a region of a page in page points, at a number of pixels per point.
public struct RasterRequest: Equatable, Sendable {
    public let region: CGRect
    public let scale: CGFloat

    public init(region: CGRect, scale: CGFloat) {
        self.region = region
        self.scale = scale
    }
}

/// Decides which bitmaps show a page background sharply at the current zoom within a fixed memory budget.
///
/// Every page has a base image of the whole page. Up to the pixel budget it is rendered at screen
/// resolution; beyond that it stays at the budget and a detail image at screen resolution covers the
/// visible part.
public struct BackgroundRenderPlanner: Equatable, Sendable {
    /// The most pixels a base image may have.
    public var maxBasePixels: CGFloat
    /// How far a detail image extends past the visible part, as a fraction of the viewport,
    /// so that short scrolls stay inside it.
    public var detailMargin: CGFloat

    public init(maxBasePixels: CGFloat = 12_000_000, detailMargin: CGFloat = 0.25) {
        self.maxBasePixels = maxBasePixels
        self.detailMargin = detailMargin
    }

    public func baseRequest(pageSize: CGSize, pixelsPerPoint: CGFloat) -> RasterRequest {
        let page = CGRect(origin: .zero, size: pageSize)
        let budgetScale = (maxBasePixels / (pageSize.width * pageSize.height)).squareRoot()
        let scale = min(pixelsPerPoint, budgetScale)
        return RasterRequest(region: PixelGrid.snapOutward(page, pixelsPerPoint: scale), scale: scale)
    }

    /// The detail image for the visible part of a page, or `nil` when the base image is sharp enough
    /// or nothing of the page is visible. Returns `current` for as long as it still serves.
    ///
    /// - Parameter visibleRect: The viewport in page points.
    public func detailRequest(
        pageSize: CGSize,
        visibleRect: CGRect,
        pixelsPerPoint: CGFloat,
        current: RasterRequest?
    ) -> RasterRequest? {
        let base = baseRequest(pageSize: pageSize, pixelsPerPoint: pixelsPerPoint)
        guard pixelsPerPoint > base.scale else { return nil }

        let page = CGRect(origin: .zero, size: pageSize)
        let visible = visibleRect.intersection(page)
        guard !visible.isNull, !visible.isEmpty else { return nil }

        if let current, current.scale == pixelsPerPoint, current.region.contains(visible) {
            return current
        }
        let padded = visible
            .insetBy(dx: -visibleRect.width * detailMargin, dy: -visibleRect.height * detailMargin)
            .intersection(page)
        return RasterRequest(region: PixelGrid.snapOutward(padded, pixelsPerPoint: pixelsPerPoint), scale: pixelsPerPoint)
    }
}
