import UIKit

/// The outline of the eraser under the pencil while it erases, so that it is clear what it takes.
final class EraserIndicator: UIView {
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

/// Takes the eraser's touch on the canvas from the moment it lands, so that erasing starts at once.
///
/// One pencil or finger erases. A second finger hands the touch over to scrolling and zooming; while a
/// pencil erases, a resting hand does nothing.
final class EraserGestureRecognizer: UIGestureRecognizer {
    private var eraser: UITouch?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let eraser {
            if eraser.type == .direct {
                state = .cancelled
            } else {
                touches.forEach { ignore($0, for: event) }
            }
            return
        }
        guard touches.count == 1, let touch = touches.first else {
            state = .failed
            return
        }
        eraser = touch
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let eraser, touches.contains(eraser) {
            state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let eraser, touches.contains(eraser) {
            state = .ended
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if let eraser, touches.contains(eraser) {
            state = .cancelled
        }
    }

    override func reset() {
        eraser = nil
    }
}
