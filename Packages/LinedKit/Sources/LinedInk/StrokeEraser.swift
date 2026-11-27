import CoreGraphics

/// Cuts a piece out of a line that an eraser touched, leaving the rest as separate lines.
public enum StrokeEraser {
    /// A point of a line: where it lies and how far its ink reaches around it.
    public struct LinePoint: Equatable, Sendable {
        public var location: CGPoint
        public var reach: CGFloat
        /// Whether the point can be erased. A point that the line does not show cannot.
        public var isErasable: Bool

        public init(location: CGPoint, reach: CGFloat, isErasable: Bool = true) {
            self.location = location
            self.reach = reach
            self.isErasable = isErasable
        }
    }

    /// The runs of `points` that remain after an eraser of `radius` swept from `start` to `end`, or
    /// `nil` when it touched none of the line's ink.
    ///
    /// The piece that goes is what lies under the eraser and, along the line, `margin` beyond it on
    /// either side, so that even a light touch takes a visible piece out of the line. A run of a
    /// single point is dropped: it draws no line.
    public static func remainingRuns(
        of points: [LinePoint],
        sweptFrom start: CGPoint,
        to end: CGPoint,
        radius: CGFloat,
        margin: CGFloat
    ) -> [Range<Int>]? {
        var isTouched = points.map { point in
            point.isErasable && distance(from: point.location, toSegmentFrom: start, to: end) <= radius + point.reach
        }
        // Between two points far apart, the eraser can touch the line and neither point.
        for index in points.indices.dropLast() where !isTouched[index] && !isTouched[index + 1] {
            let (first, second) = (points[index], points[index + 1])
            guard first.isErasable, second.isErasable else { continue }
            let gap = distance(betweenSegmentFrom: first.location, to: second.location, andSegmentFrom: start, to: end)
            if gap <= radius + min(first.reach, second.reach) {
                isTouched[index] = true
                isTouched[index + 1] = true
            }
        }
        guard isTouched.contains(true) else { return nil }
        let along = lengthsAlong(points)
        // How far along the line each point lies from the nearest touched point before and after it.
        var fromBefore = [CGFloat](repeating: .infinity, count: points.count)
        var lastTouched: CGFloat?
        for index in points.indices {
            if isTouched[index] { lastTouched = along[index] }
            if let lastTouched { fromBefore[index] = along[index] - lastTouched }
        }
        var fromAfter = [CGFloat](repeating: .infinity, count: points.count)
        var nextTouched: CGFloat?
        for index in points.indices.reversed() {
            if isTouched[index] { nextTouched = along[index] }
            if let nextTouched { fromAfter[index] = nextTouched - along[index] }
        }
        let erased = points.indices.map { index in
            points[index].isErasable && min(fromBefore[index], fromAfter[index]) <= margin
        }

        var runs: [Range<Int>] = []
        var runStart: Int?
        for index in points.indices {
            if erased[index] {
                if let first = runStart, index - first > 1 { runs.append(first..<index) }
                runStart = nil
            } else if runStart == nil {
                runStart = index
            }
        }
        if let first = runStart, points.count - first > 1 { runs.append(first..<points.count) }
        return runs
    }

    /// The distance of each point from the first one, along the line.
    private static func lengthsAlong(_ points: [LinePoint]) -> [CGFloat] {
        var lengths: [CGFloat] = []
        lengths.reserveCapacity(points.count)
        var total: CGFloat = 0
        for index in points.indices {
            if index > 0 {
                let previous = points[index - 1].location
                total += hypot(points[index].location.x - previous.x, points[index].location.y - previous.y)
            }
            lengths.append(total)
        }
        return lengths
    }

    static func distance(
        betweenSegmentFrom a: CGPoint,
        to b: CGPoint,
        andSegmentFrom c: CGPoint,
        to d: CGPoint
    ) -> CGFloat {
        if segmentsCross(a, b, c, d) { return 0 }
        return min(
            distance(from: a, toSegmentFrom: c, to: d),
            distance(from: b, toSegmentFrom: c, to: d),
            distance(from: c, toSegmentFrom: a, to: b),
            distance(from: d, toSegmentFrom: a, to: b)
        )
    }

    private static func segmentsCross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func side(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        let abc = side(a, b, c), abd = side(a, b, d), cda = side(c, d, a), cdb = side(c, d, b)
        return abc * abd < 0 && cda * cdb < 0
    }

    static func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let segment = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let lengthSquared = segment.x * segment.x + segment.y * segment.y
        let along = lengthSquared == 0
            ? 0
            : min(max(((point.x - start.x) * segment.x + (point.y - start.y) * segment.y) / lengthSquared, 0), 1)
        let nearest = CGPoint(x: start.x + along * segment.x, y: start.y + along * segment.y)
        return hypot(point.x - nearest.x, point.y - nearest.y)
    }
}
