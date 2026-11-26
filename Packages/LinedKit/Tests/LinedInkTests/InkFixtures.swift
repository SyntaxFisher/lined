import CoreGraphics
import LinedInk

/// A stroke reduced to what the page logic looks at: a straight line from its start, drawn as the
/// rectangle between its ends.
struct TestStroke: InkStroke, Equatable {
    var start: CGPoint
    var colour = "black"
    /// From the start to the end of the line.
    var reach = CGVector.zero
    /// The part of the line's rectangle that is drawn, when the stroke has been cut.
    var clip: CGRect?

    init(_ x: CGFloat, _ y: CGFloat, colour: String = "black", reach: CGVector = .zero) {
        start = CGPoint(x: x, y: y)
        self.colour = colour
        self.reach = reach
    }

    var bounds: CGRect {
        clip ?? CGRect(x: start.x, y: start.y, width: 0, height: 0)
            .union(CGRect(x: start.x + reach.dx, y: start.y + reach.dy, width: 0, height: 0))
    }

    func moved(by offset: CGVector) -> TestStroke {
        var stroke = self
        stroke.start = CGPoint(x: start.x + offset.dx, y: start.y + offset.dy)
        stroke.clip = clip?.offsetBy(dx: offset.dx, dy: offset.dy)
        return stroke
    }

    func clipped(to rect: CGRect) -> TestStroke? {
        let drawn = bounds.intersection(rect)
        guard !drawn.isNull else { return nil }
        var stroke = self
        stroke.clip = drawn
        return stroke
    }

    func fingerprint(into hasher: inout Hasher, relativeTo origin: CGPoint) {
        InkFingerprint.combine(start, relativeTo: origin, into: &hasher)
        hasher.combine(colour)
        if let clip {
            InkFingerprint.combine(clip.origin, relativeTo: origin, into: &hasher)
            hasher.combine(clip.width)
            hasher.combine(clip.height)
        }
    }
}
