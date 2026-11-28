import UIKit

/// Watches the pen draw a line and tells when it comes to rest on the canvas at the line's end, and
/// where it goes from there if that was the end of the line.
///
/// It only watches: it never recognises, so the touch stays with whatever draws the line.
final class PenHoldGestureRecognizer: UIGestureRecognizer {
    private enum Hold {
        static let duration: TimeInterval = 0.5
        /// A pen at rest still wanders this far, in screen points.
        static let reach: CGFloat = 6
    }

    private let coordinates: UIView
    private let onHold: ([CGPoint]) -> Bool
    private let onPull: (CGPoint, CGPoint) -> Void
    private let onRelease: () -> Void
    private var isHolding = false
    /// Where the pen left its resting place after the line had ended.
    private var grip: CGPoint?
    private var pen: UITouch?
    private var line: [CGPoint] = []
    /// Where the pen was when it last moved out of reach of where it was before.
    private var restingPlace = CGPoint.zero
    private var rest: Timer?

    /// - Parameters:
    ///   - coordinates: The view in whose coordinates the line is told.
    ///   - onHold: Called with the points of the line so far whenever the pen rests. It returns
    ///     whether that was the end of the line; if not, the pen may draw on and rest again.
    ///   - onPull: Called after the end of the line while the pen moves on without lifting, with
    ///     where it left its resting place and where it is.
    ///   - onRelease: Called when the pen lifts after the end of the line.
    init(
        coordinates: UIView,
        onHold: @escaping ([CGPoint]) -> Bool,
        onPull: @escaping (CGPoint, CGPoint) -> Void,
        onRelease: @escaping () -> Void
    ) {
        self.coordinates = coordinates
        self.onHold = onHold
        self.onPull = onPull
        self.onRelease = onRelease
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesEnded = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard pen == nil, touches.count == 1, let touch = touches.first else {
            // A second finger takes over to scroll or zoom.
            state = .failed
            return
        }
        pen = touch
        line = [touch.preciseLocation(in: coordinates)]
        startResting(at: touch.location(in: nil))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let pen, touches.contains(pen) else { return }
        guard !isHolding else {
            pull(with: pen)
            return
        }
        line += (event.coalescedTouches(for: pen) ?? [pen]).map { $0.preciseLocation(in: coordinates) }
        let location = pen.location(in: nil)
        if hypot(location.x - restingPlace.x, location.y - restingPlace.y) > Hold.reach {
            startResting(at: location)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func reset() {
        if isHolding {
            isHolding = false
            onRelease()
        }
        grip = nil
        rest?.invalidate()
        rest = nil
        pen = nil
        line = []
    }

    private func startResting(at place: CGPoint) {
        restingPlace = place
        rest?.invalidate()
        rest = Timer.scheduledTimer(withTimeInterval: Hold.duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.penDidRest() }
        }
    }

    private func penDidRest() {
        guard pen != nil, !isHolding else { return }
        isHolding = onHold(line)
    }

    private func pull(with pen: UITouch) {
        let location = pen.location(in: nil)
        let place = pen.preciseLocation(in: coordinates)
        if grip == nil, hypot(location.x - restingPlace.x, location.y - restingPlace.y) > Hold.reach {
            grip = place
        }
        if let grip {
            onPull(grip, place)
        }
    }
}
