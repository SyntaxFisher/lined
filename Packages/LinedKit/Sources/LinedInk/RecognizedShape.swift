import CoreGraphics
import Foundation

/// A geometric shape that a line drawn by hand comes close to.
public enum RecognizedShape: Equatable, Sendable {
    /// Straight sides from corner to corner. A straight line has two corners; a closed shape's last
    /// side leads back to its first corner.
    case polyline(corners: [CGPoint], isClosed: Bool)
    /// An ellipse whose first semi-axis is turned by `rotation` from the x-axis. A circle has two equal semi-axes.
    case ellipse(center: CGPoint, semiAxes: CGSize, rotation: CGFloat)

    /// The control points of a uniform cubic spline that draws the shape, at most `spacing` apart.
    ///
    /// Such a spline turns sharply only where a control point comes three times, so every corner does.
    public func splineControlPoints(spacing: CGFloat) -> [CGPoint] {
        switch self {
        case .polyline(let corners, let isClosed):
            let stops = isClosed ? corners + corners.prefix(1) : corners
            var points: [CGPoint] = []
            for (start, end) in zip(stops, stops.dropFirst()) {
                let steps = max(1, Int((start.distance(to: end) / spacing).rounded(.up)))
                points += [start, start, start]
                points += (1..<steps).map { start.interpolated(to: end, by: CGFloat($0) / CGFloat(steps)) }
            }
            if let last = stops.last {
                points += [last, last, last]
            }
            return points
        case .ellipse(let center, let semiAxes, let rotation):
            let circumference = 2 * CGFloat.pi * max(semiAxes.width, semiAxes.height)
            let steps = max(24, Int((circumference / spacing).rounded(.up)))
            let turn = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: rotation)
            // The line overlaps itself a little where it closes, so that no gap shows there.
            return (0...(steps + 2)).map { step in
                let angle = 2 * CGFloat.pi * CGFloat(step) / CGFloat(steps)
                return CGPoint(x: semiAxes.width * cos(angle), y: semiAxes.height * sin(angle)).applying(turn)
            }
        }
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }

    func interpolated(to other: CGPoint, by fraction: CGFloat) -> CGPoint {
        CGPoint(x: x + (other.x - x) * fraction, y: y + (other.y - y) * fraction)
    }
}
