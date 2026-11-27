import UIKit

/// The outline of the eraser under the pencil while it erases, so that it is clear what it takes.
final class EraserIndicator: UIView {
    /// The diameter in screen points for an eraser that takes whole strokes, which has no width of its own.
    static let strokeEraserDiameter: CGFloat = 14

    private let outline = CAShapeLayer()
    private let halo = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        // Light around a dark line, so that the outline shows on paper, on ink and on the desk alike.
        halo.fillColor = UIColor.white.withAlphaComponent(0.35).cgColor
        halo.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        halo.lineWidth = 3
        outline.fillColor = nil
        outline.strokeColor = UIColor(white: 0.3, alpha: 1).cgColor
        outline.lineWidth = 1
        layer.addSublayer(halo)
        layer.addSublayer(outline)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows the eraser centred on `point`, in the coordinates of the superview.
    func show(at point: CGPoint, diameter: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        center = point
        let path = UIBezierPath(ovalIn: bounds).cgPath
        halo.path = path
        outline.path = path
        isHidden = false
        CATransaction.commit()
    }

    func hide() {
        isHidden = true
    }
}

/// Follows a single touch on a view without taking part in its gestures.
final class TouchFollower: UIGestureRecognizer, UIGestureRecognizerDelegate {
    /// Called with the touch's place in `coordinateSpace` as it moves, and with `nil` once it is gone.
    var onChange: ((CGPoint?) -> Void)?
    /// Whether a touch that begins is one to follow.
    var shouldFollow: (UITouch) -> Bool = { _ in true }
    weak var coordinateSpace: UIView?

    private var followed: UITouch?

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard followed == nil, touches.count == 1, let touch = touches.first, shouldFollow(touch) else {
            stopFollowing()
            return
        }
        followed = touch
        report(touch, in: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let followed, touches.contains(followed) {
            report(followed, in: event)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        stopFollowing()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        stopFollowing()
    }

    override func reset() {
        followed = nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    /// Reports where the touch is about to be, as PencilKit draws there too.
    private func report(_ touch: UITouch, in event: UIEvent) {
        let latest = event.predictedTouches(for: touch)?.last ?? touch
        onChange?(latest.location(in: coordinateSpace ?? view))
    }

    private func stopFollowing() {
        followed = nil
        onChange?(nil)
        state = .failed
    }
}
