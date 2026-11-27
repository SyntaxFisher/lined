import CoreGraphics

/// Erases the parts of a line that an eraser sweeps over, leaving the rest as separate lines.
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

    /// The runs of `points` that remain after an eraser of `radius` swept from `start` to `end`.
    ///
    /// A run of a single point is dropped: it draws no line. Returns `nil` when the eraser touched none
    /// of the points, so that an untouched line is left as it is.
    public static func remainingRuns(
        of points: [LinePoint],
        sweptFrom start: CGPoint,
        to end: CGPoint,
        radius: CGFloat
    ) -> [Range<Int>]? {
        let erased = points.map { point in
            point.isErasable && distance(from: point.location, toSegmentFrom: start, to: end) <= radius + point.reach
        }
        guard erased.contains(true) else { return nil }
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
