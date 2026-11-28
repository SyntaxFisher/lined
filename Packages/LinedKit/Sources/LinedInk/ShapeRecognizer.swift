import CoreGraphics
import Foundation

/// Finds the geometric shape a line drawn by hand comes closest to.
///
/// A line whose ends are far apart is a straight line or a few straight sides. A line that returns to
/// its start is an ellipse or a polygon, whichever it follows more closely; a rectangle, a square and
/// a circle are recognised as what they are. Sides that are nearly horizontal or vertical become so.
/// A line that follows none of these closely is no shape.
public enum ShapeRecognizer {
    private enum Tolerance {
        static let sampleCount = 96
        /// The ends of a closed shape are no further apart than this part of the line's length.
        static let closingGap: CGFloat = 0.12

        /// How far an open line may stray from straight sides before it gets a corner, as a part of its length.
        static let openCorner: CGFloat = 0.05
        static let openCornerLimit = 5
        static let openSideLength: CGFloat = 0.12
        /// Sides through corners follow a drawn line this closely on average, as a part of its length.
        /// An arc cut into sides stays further away.
        static let openError: CGFloat = 0.01
        /// How far the middle of a side may bow away from a straight line, as a part of the side's length.
        static let openSideBow: CGFloat = 0.035
        /// An open line turns at least this much at a corner. An arc cut into sides turns less.
        static let openCornerTurn: CGFloat = 45 * .pi / 180

        /// How far a closed line may stray from straight sides before it gets a corner, as a part of
        /// the diagonal of its bounds. The other closed tolerances are parts of the diagonal as well.
        static let closedCorner: CGFloat = 0.06
        static let closedSideLength: CGFloat = 0.12
        static let closedError: CGFloat = 0.04
        /// A round line that has no corners is an ellipse even when it is drawn this unevenly.
        static let roundError: CGFloat = 0.06
        /// How far the middles of a polygon's sides bow away from straight lines on average, as a
        /// part of each side's length.
        static let closedSideBow: CGFloat = 0.025
        /// A corner that turns less than this is none.
        static let cornerTurn: CGFloat = 30 * .pi / 180
        static let polygonCorners = 3...6
        /// Every corner beyond the third makes a polygon this much less likely than an ellipse:
        /// sides through many corners follow any round line.
        static let errorPerExtraCorner: CGFloat = 0.3

        static let rightAngle: CGFloat = 20 * .pi / 180
        static let rectangleAxisSnap: CGFloat = 8 * .pi / 180
        static let squareSideRatio: CGFloat = 0.9
        static let sideAxisSnap: CGFloat = 3 * .pi / 180
    }

    public static func shape(for line: [CGPoint]) -> RecognizedShape? {
        let length = zip(line, line.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        guard length > 0 else { return nil }
        let points = resampled(line, length: length, count: Tolerance.sampleCount)
        if points[0].distance(to: points[points.count - 1]) > Tolerance.closingGap * length {
            return openShape(points, length: length)
        }
        return closedShape(points)
    }

    // MARK: Open lines

    private static func openShape(_ points: [CGPoint], length: CGFloat) -> RecognizedShape? {
        let cornerIndices = simplified(points, from: 0, to: points.count - 1, tolerance: Tolerance.openCorner * length)
        if cornerIndices.count == 2 {
            return .polyline(corners: straightened([points[0], points[points.count - 1]], isClosed: false), isClosed: false)
        }
        guard cornerIndices.count <= Tolerance.openCornerLimit else { return nil }
        let sides = zip(cornerIndices, cornerIndices.dropFirst()).map { Array(points[$0...$1]) }
        guard sides.allSatisfy({ $0[0].distance(to: $0[$0.count - 1]) >= Tolerance.openSideLength * length }) else { return nil }

        let lines = sides.map(FittedLine.init(through:))
        var corners = [lines[0].projection(of: points[0])]
        for index in 1..<lines.count {
            corners.append(lines[index - 1].intersection(with: lines[index], near: points[cornerIndices[index]], within: 0.2 * length))
        }
        corners.append(lines[lines.count - 1].projection(of: points[points.count - 1]))

        let turns = zip(lines, lines.dropFirst()).map { first, second in
            acos(min(1, abs(first.direction.dx * second.direction.dx + first.direction.dy * second.direction.dy)))
        }
        let isStraightSided = zip(lines, sides).allSatisfy { line, side in
            line.bow(of: side) <= Tolerance.openSideBow * side[0].distance(to: side[side.count - 1])
        }
        guard isStraightSided, turns.allSatisfy({ $0 >= Tolerance.openCornerTurn }),
              meanDistance(from: points, toSidesThrough: corners) <= Tolerance.openError * length
        else { return nil }
        return .polyline(corners: straightened(corners, isClosed: false), isClosed: false)
    }

    // MARK: Closed lines

    private static func closedShape(_ points: [CGPoint]) -> RecognizedShape? {
        let bounds = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        let diagonal = hypot(bounds.width, bounds.height)
        guard diagonal > 0 else { return nil }

        let ellipse = Ellipse(around: points)
        let ellipseError = ellipse.map { $0.meanDistance(from: points) / diagonal } ?? .infinity
        let polygon = polygon(through: points, diagonal: diagonal)
        let polygonError = polygon.map { corners in
            let error = meanDistance(from: points, toSidesThrough: corners + corners.prefix(1)) / diagonal
            return error * (1 + Tolerance.errorPerExtraCorner * CGFloat(corners.count - 3))
        } ?? .infinity

        if let polygon, polygonError < ellipseError, polygonError <= Tolerance.closedError {
            return .polyline(corners: rectangle(from: polygon) ?? straightened(polygon, isClosed: true), isClosed: true)
        }
        return ellipseError <= (polygon == nil ? Tolerance.roundError : Tolerance.closedError) ? ellipse?.shape : nil
    }

    /// The corners of the polygon a closed line follows, each where the straight lines through its
    /// two sides meet, so that a corner drawn round becomes sharp.
    private static func polygon(through points: [CGPoint], diagonal: CGFloat) -> [CGPoint]? {
        let count = points.count
        let center = centroid(of: points)
        // The point farthest from the middle is a corner, if the line has any. The loop starts there.
        let start = points.indices.max { points[$0].distance(to: center) < points[$1].distance(to: center) } ?? 0
        let loop = (0...count).map { points[(start + $0) % count] }
        let opposite = loop.indices.max { loop[$0].distance(to: loop[0]) < loop[$1].distance(to: loop[0]) } ?? 0
        guard opposite > 0, opposite < count else { return nil }

        let tolerance = Tolerance.closedCorner * diagonal
        var indices = simplified(loop, from: 0, to: opposite, tolerance: tolerance)
            + simplified(loop, from: opposite, to: count, tolerance: tolerance).dropFirst().dropLast()

        func turn(at position: Int) -> CGFloat {
            let previous = loop[indices[(position + indices.count - 1) % indices.count]]
            let corner = loop[indices[position]]
            let next = loop[indices[(position + 1) % indices.count]]
            return abs(angle(from: CGVector(from: previous, to: corner), to: CGVector(from: corner, to: next)))
        }
        while indices.count > 3 {
            let straightest = indices.indices.min { turn(at: $0) < turn(at: $1) }!
            let shortSides = indices.indices.filter {
                loop[indices[$0]].distance(to: loop[indices[($0 + 1) % indices.count]]) < Tolerance.closedSideLength * diagonal
            }
            if turn(at: straightest) < Tolerance.cornerTurn {
                indices.remove(at: straightest)
            } else if let side = shortSides.first {
                let next = (side + 1) % indices.count
                indices.remove(at: turn(at: side) < turn(at: next) ? side : next)
            } else {
                break
            }
        }
        guard Tolerance.polygonCorners.contains(indices.count),
              indices.indices.allSatisfy({ turn(at: $0) >= Tolerance.cornerTurn })
        else { return nil }

        let sides = indices.indices.map { position in
            let from = indices[position]
            var to = indices[(position + 1) % indices.count]
            if to <= from { to += count }
            return (from...to).map { loop[$0 % count] }
        }
        let lines = sides.map(FittedLine.init(through:))
        // A round line cut into sides bows away from every one of them.
        let bow = zip(lines, sides).reduce(0) { $0 + $1.0.bow(of: $1.1) / $1.1[0].distance(to: $1.1[$1.1.count - 1]) }
        guard bow / CGFloat(sides.count) <= Tolerance.closedSideBow else { return nil }
        return indices.indices.map { position in
            lines[(position + lines.count - 1) % lines.count]
                .intersection(with: lines[position], near: loop[indices[position]], within: 0.2 * diagonal)
        }
    }

    /// The rectangle four corners with right angles stand for: upright when it is nearly so, and a
    /// square when its sides are nearly equal.
    private static func rectangle(from corners: [CGPoint]) -> [CGPoint]? {
        guard corners.count == 4 else { return nil }
        let sides = (0..<4).map { CGVector(from: corners[$0], to: corners[($0 + 1) % 4]) }
        let hasRightAngles = (0..<4).allSatisfy { abs(abs(angle(from: sides[$0], to: sides[($0 + 1) % 4])) - .pi / 2) <= Tolerance.rightAngle }
        guard hasRightAngles else { return nil }

        // Every side points along the rectangle or across it; four times its angle is the same for both.
        let sum = sides.reduce(CGVector.zero) { sum, side in
            let direction = 4 * atan2(side.dy, side.dx)
            let weight = hypot(side.dx, side.dy)
            return CGVector(dx: sum.dx + weight * cos(direction), dy: sum.dy + weight * sin(direction))
        }
        var rotation = atan2(sum.dy, sum.dx) / 4
        if abs(rotation) <= Tolerance.rectangleAxisSnap {
            rotation = 0
        }

        let turn = CGAffineTransform(rotationAngle: rotation)
        let upright = corners.map { $0.applying(turn.inverted()) }
        let xs = upright.map(\.x).sorted()
        let ys = upright.map(\.y).sorted()
        let middle = CGPoint(x: xs.reduce(0, +) / 4, y: ys.reduce(0, +) / 4)
        var half = CGSize(width: (xs[2] + xs[3] - xs[0] - xs[1]) / 4, height: (ys[2] + ys[3] - ys[0] - ys[1]) / 4)
        if min(half.width, half.height) >= Tolerance.squareSideRatio * max(half.width, half.height) {
            let side = (half.width + half.height) / 2
            half = CGSize(width: side, height: side)
        }
        return [(-1, -1), (1, -1), (1, 1), (-1, 1)].map { x, y in
            CGPoint(x: middle.x + CGFloat(x) * half.width, y: middle.y + CGFloat(y) * half.height).applying(turn)
        }
    }

    /// Makes sides that are nearly horizontal or vertical exactly so.
    private static func straightened(_ corners: [CGPoint], isClosed: Bool) -> [CGPoint] {
        var corners = corners
        let sideCount = isClosed ? corners.count : corners.count - 1
        for side in 0..<sideCount {
            let start = side
            let end = (side + 1) % corners.count
            let direction = atan2(abs(corners[end].y - corners[start].y), abs(corners[end].x - corners[start].x))
            if direction <= Tolerance.sideAxisSnap {
                let y = (corners[start].y + corners[end].y) / 2
                corners[start].y = y
                corners[end].y = y
            } else if direction >= .pi / 2 - Tolerance.sideAxisSnap {
                let x = (corners[start].x + corners[end].x) / 2
                corners[start].x = x
                corners[end].x = x
            }
        }
        return corners
    }

    // MARK: Geometry

    /// `count` points along the line, evenly apart.
    private static func resampled(_ line: [CGPoint], length: CGFloat, count: Int) -> [CGPoint] {
        let step = length / CGFloat(count - 1)
        var points = [line[0]]
        var travelled: CGFloat = 0
        for (start, end) in zip(line, line.dropFirst()) {
            let segment = start.distance(to: end)
            guard segment > 0 else { continue }
            while points.count < count - 1, travelled + segment >= step * CGFloat(points.count) {
                points.append(start.interpolated(to: end, by: (step * CGFloat(points.count) - travelled) / segment))
            }
            travelled += segment
        }
        points.append(line[line.count - 1])
        return points
    }

    /// The indices of the points that straight sides must pass through to stay within `tolerance` of
    /// the line between two of its points, those two included.
    private static func simplified(_ points: [CGPoint], from: Int, to: Int, tolerance: CGFloat) -> [Int] {
        guard to > from + 1 else { return [from, to] }
        let inner = (from + 1)..<to
        let farthest = inner.max {
            distance(from: points[$0], toSegmentFrom: points[from], to: points[to])
                < distance(from: points[$1], toSegmentFrom: points[from], to: points[to])
        }!
        guard distance(from: points[farthest], toSegmentFrom: points[from], to: points[to]) > tolerance else { return [from, to] }
        return simplified(points, from: from, to: farthest, tolerance: tolerance).dropLast()
            + simplified(points, from: farthest, to: to, tolerance: tolerance)
    }

    private static func meanDistance(from points: [CGPoint], toSidesThrough corners: [CGPoint]) -> CGFloat {
        let sides = Array(zip(corners, corners.dropFirst()))
        let total = points.reduce(0) { total, point in
            total + (sides.map { distance(from: point, toSegmentFrom: $0.0, to: $0.1) }.min() ?? 0)
        }
        return total / CGFloat(points.count)
    }

    private static func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let side = CGVector(from: start, to: end)
        let squaredLength = side.dx * side.dx + side.dy * side.dy
        guard squaredLength > 0 else { return point.distance(to: start) }
        let along = ((point.x - start.x) * side.dx + (point.y - start.y) * side.dy) / squaredLength
        return point.distance(to: start.interpolated(to: end, by: min(max(along, 0), 1)))
    }

    /// The angle by which `first` turns to point like `second`, from -π to π.
    private static func angle(from first: CGVector, to second: CGVector) -> CGFloat {
        atan2(first.dx * second.dy - first.dy * second.dx, first.dx * second.dx + first.dy * second.dy)
    }

    fileprivate static func centroid(of points: [CGPoint]) -> CGPoint {
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    /// The direction along which the points spread most, as an angle from the x-axis.
    fileprivate static func principalDirection(of points: [CGPoint], around center: CGPoint) -> CGFloat {
        var xx: CGFloat = 0, yy: CGFloat = 0, xy: CGFloat = 0
        for point in points {
            let dx = point.x - center.x, dy = point.y - center.y
            xx += dx * dx
            yy += dy * dy
            xy += dx * dy
        }
        return atan2(2 * xy, xx - yy) / 2
    }
}

/// The straight line that passes closest to a set of points.
private struct FittedLine {
    let point: CGPoint
    let direction: CGVector

    /// Fits the line to the middle of the points: a side drawn by hand bends towards its corners.
    init(through points: [CGPoint]) {
        let middle = Self.middle(of: points)
        point = ShapeRecognizer.centroid(of: middle)
        let angle = ShapeRecognizer.principalDirection(of: middle, around: point)
        direction = CGVector(dx: cos(angle), dy: sin(angle))
    }

    private static func middle(of points: [CGPoint]) -> [CGPoint] {
        let margin = points.count / 5
        return points.count - 2 * margin >= 2 ? Array(points[margin..<(points.count - margin)]) : points
    }

    /// How far the middle of the points strays from the line at most.
    func bow(of points: [CGPoint]) -> CGFloat {
        Self.middle(of: points).map { $0.distance(to: projection(of: $0)) }.max() ?? 0
    }

    func projection(of other: CGPoint) -> CGPoint {
        let along = (other.x - point.x) * direction.dx + (other.y - point.y) * direction.dy
        return CGPoint(x: point.x + along * direction.dx, y: point.y + along * direction.dy)
    }

    /// Where the two lines meet, or `corner` when they are nearly parallel or meet far from it.
    func intersection(with other: FittedLine, near corner: CGPoint, within reach: CGFloat) -> CGPoint {
        let cross = direction.dx * other.direction.dy - direction.dy * other.direction.dx
        guard abs(cross) > 0.2 else { return corner }
        let between = CGVector(from: point, to: other.point)
        let along = (between.dx * other.direction.dy - between.dy * other.direction.dx) / cross
        let meeting = CGPoint(x: point.x + along * direction.dx, y: point.y + along * direction.dy)
        return meeting.distance(to: corner) <= reach ? meeting : corner
    }
}

/// The ellipse that spans a closed line: turned the way the line spreads most, and as long and wide.
private struct Ellipse {
    var center: CGPoint
    var semiAxes: CGSize
    var rotation: CGFloat

    private enum Tolerance {
        static let circleAxisRatio: CGFloat = 0.82
        static let axisSnap: CGFloat = 12 * .pi / 180
    }

    init?(around points: [CGPoint]) {
        var rotation = ShapeRecognizer.principalDirection(of: points, around: ShapeRecognizer.centroid(of: points))
        if abs(rotation) <= Tolerance.axisSnap {
            rotation = 0
        } else if abs(rotation) >= .pi / 2 - Tolerance.axisSnap {
            rotation = .pi / 2
        }
        let turn = CGAffineTransform(rotationAngle: rotation)
        let upright = points.map { $0.applying(turn.inverted()) }
        let bounds = upright.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        center = CGPoint(x: bounds.midX, y: bounds.midY).applying(turn)
        semiAxes = CGSize(width: bounds.width / 2, height: bounds.height / 2)
        self.rotation = rotation
        if min(semiAxes.width, semiAxes.height) >= Tolerance.circleAxisRatio * max(semiAxes.width, semiAxes.height) {
            let radius = (semiAxes.width + semiAxes.height) / 2
            semiAxes = CGSize(width: radius, height: radius)
            self.rotation = 0
        }
    }

    var shape: RecognizedShape {
        .ellipse(center: center, semiAxes: semiAxes, rotation: rotation)
    }

    /// How far the points lie from the ellipse on average, measured along the ray from its centre.
    func meanDistance(from points: [CGPoint]) -> CGFloat {
        let upright = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: rotation).inverted()
        let total = points.reduce(0) { total, point in
            let local = point.applying(upright)
            let distance = hypot(local.x, local.y)
            let relative = hypot(local.x / semiAxes.width, local.y / semiAxes.height)
            return total + (relative > 0 ? abs(distance - distance / relative) : min(semiAxes.width, semiAxes.height))
        }
        return total / CGFloat(points.count)
    }
}

private extension CGVector {
    init(from start: CGPoint, to end: CGPoint) {
        self.init(dx: end.x - start.x, dy: end.y - start.y)
    }
}
