import CoreGraphics
import LinedInk

/// A stroke reduced to what the page logic looks at: a straight line, drawn as the rectangle between
/// its ends.
struct TestStroke: InkStroke, Equatable {
    /// Where the line begins.
    var origin: CGPoint
    var colour = "black"
    /// From the beginning to the end of the line.
    var reach = CGVector.zero
    /// The part of the line's rectangle that is drawn, when the stroke has been cut.
    var clip: CGRect?

    init(_ x: CGFloat, _ y: CGFloat, colour: String = "black", reach: CGVector = .zero) {
        origin = CGPoint(x: x, y: y)
        self.colour = colour
        self.reach = reach
    }

    /// The first point of the line that is drawn.
    var start: CGPoint {
        guard let clip else { return origin }
        for step in 0...1000 {
            let fraction = CGFloat(step) / 1000
            let point = CGPoint(x: origin.x + reach.dx * fraction, y: origin.y + reach.dy * fraction)
            if (clip.minX...clip.maxX).contains(point.x), (clip.minY...clip.maxY).contains(point.y) {
                return point
            }
        }
        return CGPoint(x: clip.midX, y: clip.midY)
    }

    var bounds: CGRect {
        clip ?? CGRect(x: origin.x, y: origin.y, width: 0, height: 0)
            .union(CGRect(x: origin.x + reach.dx, y: origin.y + reach.dy, width: 0, height: 0))
    }

    func moved(by offset: CGVector) -> TestStroke {
        var stroke = self
        stroke.origin = CGPoint(x: origin.x + offset.dx, y: origin.y + offset.dy)
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
        InkFingerprint.combine(self.origin, relativeTo: origin, into: &hasher)
        hasher.combine(colour)
        if let clip {
            InkFingerprint.combine(clip.origin, relativeTo: origin, into: &hasher)
            hasher.combine(clip.width)
            hasher.combine(clip.height)
        }
    }
}
