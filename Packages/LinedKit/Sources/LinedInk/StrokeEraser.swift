import CoreGraphics

/// Cuts a piece out of a line that an eraser touched, leaving the rest as separate lines.
public enum StrokeEraser {
    /// A point of a line: where it lies and how far its line reaches around it.
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

    /// The runs of `points` that remain once an eraser of `radius`, sweeping from `start` to `end`,
    /// touched the line.
    ///
    /// The piece that goes is what lies under the eraser and, along the line, `margin` beyond it on
    /// either side, so that even a light touch takes a clear piece out of the line. Where no point
    /// lies under the eraser, as when it only touches the edge of a wide line, the piece is centred
    /// on the point nearest to it. A run of a single point is dropped: it draws no line.
    public static func remainingRuns(
        of points: [LinePoint],
        touchedFrom start: CGPoint,
        to end: CGPoint,
        radius: CGFloat,
        margin: CGFloat
    ) -> [Range<Int>] {
        let distances = points.map { distance(from: $0.location, toSegmentFrom: start, to: end) }
        var touched = points.indices.filter { points[$0].isErasable && distances[$0] <= radius + points[$0].reach }
        if touched.isEmpty, let nearest = points.indices.filter({ points[$0].isErasable }).min(by: { distances[$0] < distances[$1] }) {
            touched = [nearest]
        }
        let along = lengthsAlong(points)
        let isTouched = Set(touched)
        // How far along the line each point lies from the nearest touched point before and after it.
        var fromBefore = [CGFloat](repeating: .infinity, count: points.count)
        var lastTouched: CGFloat?
        for index in points.indices {
            if isTouched.contains(index) { lastTouched = along[index] }
            if let lastTouched { fromBefore[index] = along[index] - lastTouched }
        }
        var fromAfter = [CGFloat](repeating: .infinity, count: points.count)
        var nextTouched: CGFloat?
        for index in points.indices.reversed() {
            if isTouched.contains(index) { nextTouched = along[index] }
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

    public static func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let segment = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let lengthSquared = segment.x * segment.x + segment.y * segment.y
        let along = lengthSquared == 0
            ? 0
            : min(max(((point.x - start.x) * segment.x + (point.y - start.y) * segment.y) / lengthSquared, 0), 1)
        let nearest = CGPoint(x: start.x + along * segment.x, y: start.y + along * segment.y)
        return hypot(point.x - nearest.x, point.y - nearest.y)
    }
}
