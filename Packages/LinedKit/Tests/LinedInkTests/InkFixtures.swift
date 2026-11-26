import CoreGraphics
import LinedInk

/// A stroke reduced to what the page logic looks at.
struct TestStroke: InkStroke, Equatable {
    var start: CGPoint
    var colour = "black"

    init(_ x: CGFloat, _ y: CGFloat, colour: String = "black") {
        start = CGPoint(x: x, y: y)
        self.colour = colour
    }

    func moved(by offset: CGVector) -> TestStroke {
        TestStroke(start.x + offset.dx, start.y + offset.dy, colour: colour)
    }

    func fingerprint(into hasher: inout Hasher, relativeTo origin: CGPoint) {
        InkFingerprint.combine(start, relativeTo: origin, into: &hasher)
        hasher.combine(colour)
    }
}
