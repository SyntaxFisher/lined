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
        case .ellipse(_, let semiAxes, _):
            let circumference = 2 * CGFloat.pi * max(semiAxes.width, semiAxes.height)
            // A small ellipse needs its points close together as well: where they are far apart
            // for its size, the ends of the spline stand out of the line.
            let steps = max(Self.fewestEllipseSteps, Int((circumference / spacing).rounded(.up)))
            return ellipsePoints(steps: (steps + 3) / 4 * 4)
        }
    }
}

extension RecognizedShape {
    private static let fewestEllipseSteps = 72
    /// How many control points an ellipse has beyond one for each step around it.
    private static let ellipseOverlap = 3

    /// The shape whose spline has these control points, or `nil` when they are not those of a shape:
    /// the points of a line drawn by hand never are.
    public init?(splineControlPoints points: [CGPoint]) {
        guard points.count >= 6 else { return nil }
        let reading = points[0] == points[1] ? Self.polyline(readFrom: points) : Self.ellipse(readFrom: points)
        guard let reading else { return nil }
        self = reading
    }

    private static func polyline(readFrom points: [CGPoint]) -> RecognizedShape? {
        var corners: [CGPoint] = []
        var index = 0
        while index < points.count {
            var end = index
            while end + 1 < points.count, points[end + 1] == points[index] { end += 1 }
            if end - index == 2 {
                corners.append(points[index])
            } else if end != index {
                return nil
            } else if let last = corners.last, index + 1 < points.count {
                // A point between two corners lies on the side from the one towards the next.
                let ahead = points[(index + 1)...].first { $0 != points[index] } ?? points[index]
                let side = CGVector(dx: ahead.x - last.x, dy: ahead.y - last.y)
                let offset = CGVector(dx: points[index].x - last.x, dy: points[index].y - last.y)
                let tolerance = 0.001 * max(1, hypot(side.dx, side.dy)) * max(1, hypot(offset.dx, offset.dy))
                guard abs(side.dx * offset.dy - side.dy * offset.dx) <= tolerance else { return nil }
            } else {
                return nil
            }
            index = end + 1
        }
        guard corners.count >= 2, points[points.count - 1] == corners[corners.count - 1] else { return nil }
        let isClosed = corners.count > 3 && corners[0] == corners[corners.count - 1]
        return .polyline(corners: isClosed ? Array(corners.dropLast()) : corners, isClosed: isClosed)
    }

    private static func ellipse(readFrom points: [CGPoint]) -> RecognizedShape? {
        let steps = points.count - ellipseOverlap
        guard steps >= fewestEllipseSteps, steps.isMultiple(of: 4) else { return nil }
        let around = points[..<steps]
        let center = CGPoint(x: around.map(\.x).reduce(0, +) / CGFloat(steps), y: around.map(\.y).reduce(0, +) / CGFloat(steps))
        let semiAxes = CGSize(width: center.distance(to: points[0]), height: center.distance(to: points[steps / 4]))
        guard semiAxes.width > 0, semiAxes.height > 0 else { return nil }
        let shape = RecognizedShape.ellipse(
            center: center,
            semiAxes: semiAxes,
            rotation: atan2(points[0].y - center.y, points[0].x - center.x)
        )
        let expected = shape.ellipsePoints(steps: steps)
        let tolerance = 0.001 * max(1, semiAxes.width, semiAxes.height)
        guard zip(points, expected).allSatisfy({ $0.distance(to: $1) <= tolerance }) else { return nil }
        return shape
    }

    private func ellipsePoints(steps: Int) -> [CGPoint] {
        guard case .ellipse(let center, let semiAxes, let rotation) = self else { return [] }
        let turn = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: rotation)
        // The line overlaps itself a little where it closes, so that no gap shows there.
        return (0..<(steps + Self.ellipseOverlap)).map { step in
            let angle = 2 * CGFloat.pi * CGFloat(step) / CGFloat(steps)
            return CGPoint(x: semiAxes.width * cos(angle), y: semiAxes.height * sin(angle)).applying(turn)
        }
    }

    /// How far a point is from the line of the shape.
    public func distance(to point: CGPoint) -> CGFloat {
        let outline: [CGPoint]
        switch self {
        case .polyline(let corners, let isClosed): outline = isClosed ? corners + corners.prefix(1) : corners
        case .ellipse: outline = ellipsePoints(steps: Self.fewestEllipseSteps)
        }
        return zip(outline, outline.dropFirst()).map { start, end in
            let side = CGVector(dx: end.x - start.x, dy: end.y - start.y)
            let squaredLength = side.dx * side.dx + side.dy * side.dy
            guard squaredLength > 0 else { return point.distance(to: start) }
            let along = ((point.x - start.x) * side.dx + (point.y - start.y) * side.dy) / squaredLength
            return point.distance(to: start.interpolated(to: end, by: min(max(along, 0), 1)))
        }.min() ?? .infinity
    }

    // MARK: Changing a shape

    /// The point a shape turns and grows about while the pen that drew it pulls at it: where an
    /// open line starts, and the middle of a closed shape.
    public var anchor: CGPoint {
        switch self {
        case .polyline(let corners, let isClosed):
            guard isClosed else { return corners[0] }
            return CGPoint(
                x: corners.map(\.x).reduce(0, +) / CGFloat(corners.count),
                y: corners.map(\.y).reduce(0, +) / CGFloat(corners.count)
            )
        case .ellipse(let center, _, _):
            return center
        }
    }

    /// The shape turned and scaled about its anchor so that what was at `grip` comes to lie at `pen`.
    public func pulled(from grip: CGPoint, to pen: CGPoint) -> RecognizedShape {
        let anchor = anchor
        let reach = anchor.distance(to: grip)
        guard reach > 0 else { return self }
        let scale = max(anchor.distance(to: pen) / reach, 0.02)
        let turn = atan2(pen.y - anchor.y, pen.x - anchor.x) - atan2(grip.y - anchor.y, grip.x - anchor.x)
        switch self {
        case .polyline(let corners, let isClosed):
            let change = CGAffineTransform(translationX: anchor.x, y: anchor.y)
                .rotated(by: turn)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -anchor.x, y: -anchor.y)
            return .polyline(corners: corners.map { $0.applying(change) }, isClosed: isClosed)
        case .ellipse(let center, let semiAxes, let rotation):
            return .ellipse(
                center: center,
                semiAxes: CGSize(width: semiAxes.width * scale, height: semiAxes.height * scale),
                rotation: rotation + turn
            )
        }
    }

    /// The points at which a shape can be taken hold of to change it: its corners, or the four
    /// ends of an ellipse's axes.
    public var handles: [CGPoint] {
        switch self {
        case .polyline(let corners, _):
            return corners
        case .ellipse(let center, let semiAxes, let rotation):
            let turn = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: rotation)
            return [
                CGPoint(x: semiAxes.width, y: 0), CGPoint(x: 0, y: semiAxes.height),
                CGPoint(x: -semiAxes.width, y: 0), CGPoint(x: 0, y: -semiAxes.height),
            ].map { $0.applying(turn) }
        }
    }

    /// The shape with one of its handles moved. A corner goes where it is moved to; an ellipse
    /// becomes as long or as wide as the handle is far from its middle, and a circle stays one.
    public func movingHandle(at index: Int, to point: CGPoint) -> RecognizedShape {
        switch self {
        case .polyline(var corners, let isClosed):
            corners[index] = point
            return .polyline(corners: corners, isClosed: isClosed)
        case .ellipse(let center, var semiAxes, let rotation):
            let reach = max(center.distance(to: point), 0.5)
            if semiAxes.width == semiAxes.height {
                semiAxes = CGSize(width: reach, height: reach)
            } else if index.isMultiple(of: 2) {
                semiAxes.width = reach
            } else {
                semiAxes.height = reach
            }
            return .ellipse(center: center, semiAxes: semiAxes, rotation: rotation)
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
