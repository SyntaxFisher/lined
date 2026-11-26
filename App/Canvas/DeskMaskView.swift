import UIKit

/// Covers everything around the pages, above the ink, so that strokes running past a page's edge
/// do not show on the desk between and beside the pages.
final class DeskMaskView: UIView {
    override class var layerClass: AnyClass { CAShapeLayer.self }

    private var shape: CAShapeLayer { layer as! CAShapeLayer }
    private var pageFrames: [CGRect] = []

    var deskColor: UIColor = .clear {
        didSet { shape.fillColor = deskColor.cgColor }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        shape.fillRule = .evenOdd
        shape.actions = ["path": NSNull(), "fillColor": NSNull()]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// - Parameters:
    ///   - pageFrames: The pages to leave uncovered, in the view's coordinates.
    ///   - extent: The area to cover around them.
    func uncover(_ pageFrames: [CGRect], within extent: CGRect) {
        guard pageFrames != self.pageFrames || shape.path?.boundingBox != extent else { return }
        self.pageFrames = pageFrames
        let path = CGMutablePath()
        path.addRect(extent)
        pageFrames.forEach { path.addRect($0) }
        shape.path = path
    }
}
