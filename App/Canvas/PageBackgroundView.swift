import LinedLayout
import LinedRendering
import UIKit

/// Shows the paper or PDF page beneath the ink, re-rendered for the zoom it is viewed at.
///
/// The view's bounds are the page in page points; the canvas around it magnifies it.
/// A base image covers the whole page. Where the zoom exceeds what the base image may hold,
/// a detail image at screen resolution covers the visible part. An image stays on screen until
/// its replacement has finished rendering, so the page never flashes empty.
final class PageBackgroundView: UIView {
    private let renderPool: BackgroundRenderPool
    private let planner = BackgroundRenderPlanner()
    private var base = ImageSlot()
    private var detail = ImageSlot()
    private var renderer: (any PageBackgroundRenderer)?
    private var pageSize = CGSize.zero
    private var viewing: (visibleRect: CGRect, pixelsPerPoint: CGFloat)?

    init(renderPool: BackgroundRenderPool) {
        self.renderPool = renderPool
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .white
        clipsToBounds = true
        layer.borderColor = UIColor(white: 0, alpha: 0.14).cgColor
        layer.borderWidth = 0.5
        layer.addSublayer(base.layer)
        layer.addSublayer(detail.layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func display(pageSize: CGSize, renderer: any PageBackgroundRenderer) {
        reset()
        self.pageSize = pageSize
        self.renderer = renderer
        bounds = CGRect(origin: .zero, size: pageSize)
    }

    func reset() {
        releaseImages()
        renderer = nil
    }

    /// Whether the page shows no rendered image and none is on its way.
    var isBlank: Bool { base.shown == nil && base.task == nil }

    /// Drops the rendered images until the next `update`.
    func releaseImages() {
        base.clear()
        detail.clear()
        viewing = nil
    }

    /// - Parameter visibleRect: The viewport in page points.
    func update(visibleRect: CGRect, pixelsPerPoint: CGFloat) {
        viewing = (visibleRect, pixelsPerPoint)
        plan()
    }

    private func plan() {
        guard let viewing, renderer != nil else { return }

        let baseRequest = planner.baseRequest(pageSize: pageSize, pixelsPerPoint: viewing.pixelsPerPoint)
        if baseRequest != base.shown {
            render(baseRequest, into: \.base)
        }

        let detailRequest = planner.detailRequest(
            pageSize: pageSize,
            visibleRect: viewing.visibleRect,
            pixelsPerPoint: viewing.pixelsPerPoint,
            current: detail.shown
        )
        if let detailRequest {
            if detailRequest != detail.shown {
                render(detailRequest, into: \.detail)
            }
        } else {
            detail.clear()
        }
    }

    /// Starts rendering unless the slot is already busy; a busy slot plans again when it finishes,
    /// which picks up whatever the view needs by then.
    private func render(_ request: RasterRequest, into slot: ReferenceWritableKeyPath<PageBackgroundView, ImageSlot>) {
        guard self[keyPath: slot].task == nil, let renderer else { return }
        let pageSize = pageSize
        self[keyPath: slot].task = Task { [weak self, renderPool] in
            let image = await renderPool.image(of: renderer, pageSize: pageSize, request: request)
            guard let self, !Task.isCancelled else { return }
            self[keyPath: slot].task = nil
            self[keyPath: slot].show(image, for: request)
            self.plan()
        }
    }
}

/// One bitmap layer of a page background and the render that will replace its content.
private struct ImageSlot {
    let layer = CALayer()
    private(set) var shown: RasterRequest?
    var task: Task<Void, Never>?

    init() {
        layer.contentsGravity = .resize
        layer.minificationFilter = .trilinear
        layer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
    }

    mutating func show(_ image: CGImage?, for request: RasterRequest) {
        layer.frame = request.region
        layer.contents = image
        shown = request
    }

    mutating func clear() {
        task?.cancel()
        task = nil
        layer.contents = nil
        shown = nil
    }
}
