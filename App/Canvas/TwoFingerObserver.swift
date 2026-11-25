import UIKit

/// Tells when two fingers are down on its view, without ever claiming a touch.
final class TwoFingerObserver: UIGestureRecognizer {
    /// Called with `true` when a second finger comes down, and with `false` once all fingers are lifted.
    var onChange: ((Bool) -> Void)?

    private var isActive = false

    init() {
        super.init(target: nil, action: nil)
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        cancelsTouchesInView = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        // A hand resting beside a writing Pencil is no gesture.
        guard !isActive, fingersDown(in: event) >= 2, !isPencilDown(in: event) else { return }
        isActive = true
        onChange?(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        failWhenLifted(in: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        failWhenLifted(in: event)
    }

    override func reset() {
        super.reset()
        guard isActive else { return }
        isActive = false
        onChange?(false)
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    private func fingersDown(in event: UIEvent) -> Int {
        (event.touches(for: self) ?? []).count(where: \.isDown)
    }

    private func isPencilDown(in event: UIEvent) -> Bool {
        (event.allTouches ?? []).contains { $0.type == .pencil && $0.isDown }
    }

    private func failWhenLifted(in event: UIEvent) {
        if fingersDown(in: event) == 0 {
            state = .failed
        }
    }
}

private extension UITouch {
    var isDown: Bool { phase != .ended && phase != .cancelled }
}
