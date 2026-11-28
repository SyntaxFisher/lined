import UIKit

/// The knobs on a shape that was tapped, by which its corners or axes are dragged.
///
/// The view lies above the canvas and takes only the touches on its knobs; all others go through
/// to the canvas beneath.
final class ShapeHandlesView: UIView {
    private enum Knob {
        static let diameter: CGFloat = 14
        /// A touch this close to a knob's middle takes hold of it.
        static let reach: CGFloat = 22
    }

    /// Called while a knob is dragged, with its index and where it is dragged to, in this view.
    var onDrag: ((Int, CGPoint) -> Void)?
    var onDragBegin: (() -> Void)?
    var onDragEnd: (() -> Void)?

    private var knobs: [UIView] = []
    private var dragged: (index: Int, offset: CGPoint)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows a knob at each of the points, in this view's coordinates. No points, no knobs.
    func show(_ points: [CGPoint]) {
        while knobs.count > points.count {
            knobs.removeLast().removeFromSuperview()
        }
        while knobs.count < points.count {
            let knob = makeKnob()
            addSubview(knob)
            knobs.append(knob)
        }
        for (knob, point) in zip(knobs, points) {
            knob.center = point
        }
    }

    private func makeKnob() -> UIView {
        let knob = UIView(frame: CGRect(x: 0, y: 0, width: Knob.diameter, height: Knob.diameter))
        knob.isUserInteractionEnabled = false
        knob.backgroundColor = .white
        knob.layer.cornerRadius = Knob.diameter / 2
        knob.layer.borderWidth = 2
        knob.layer.borderColor = tintColor.cgColor
        knob.layer.shadowColor = UIColor.black.cgColor
        knob.layer.shadowOpacity = 0.25
        knob.layer.shadowRadius = 2
        knob.layer.shadowOffset = CGSize(width: 0, height: 1)
        return knob
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        knobs.forEach { $0.layer.borderColor = tintColor.cgColor }
    }

    private func knobIndex(near point: CGPoint) -> Int? {
        let nearest = knobs.indices.min {
            hypot(knobs[$0].center.x - point.x, knobs[$0].center.y - point.y) < hypot(knobs[$1].center.x - point.x, knobs[$1].center.y - point.y)
        }
        guard let nearest, hypot(knobs[nearest].center.x - point.x, knobs[nearest].center.y - point.y) <= Knob.reach else { return nil }
        return nearest
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        knobIndex(near: point) == nil ? nil : self
    }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        switch gesture.state {
        case .began:
            // The pan begins a little way from where the touch landed.
            let landing = CGPoint(x: location.x - gesture.translation(in: self).x, y: location.y - gesture.translation(in: self).y)
            guard let index = knobIndex(near: landing) else { return }
            let center = knobs[index].center
            dragged = (index, CGPoint(x: center.x - landing.x, y: center.y - landing.y))
            onDragBegin?()
            fallthrough
        case .changed:
            guard let dragged else { return }
            onDrag?(dragged.index, CGPoint(x: location.x + dragged.offset.x, y: location.y + dragged.offset.y))
        default:
            guard dragged != nil else { return }
            dragged = nil
            onDragEnd?()
        }
    }
}
