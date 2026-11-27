import LinedInk
import PencilKit
import UIKit

/// The outline of the eraser under the pencil while it erases, so that it is clear what it takes.
final class EraserIndicator: UIView {
    private let outline = CAShapeLayer()
    private let halo = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        // Light around a dark line, so that the outline shows on paper, on ink and on the desk alike.
        halo.fillColor = UIColor.white.withAlphaComponent(0.35).cgColor
        halo.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        halo.lineWidth = 3
        outline.fillColor = nil
        outline.strokeColor = UIColor(white: 0.3, alpha: 1).cgColor
        outline.lineWidth = 1
        layer.addSublayer(halo)
        layer.addSublayer(outline)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows the eraser centred on `point`, in the coordinates of the superview.
    func show(at point: CGPoint, diameter: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        center = point
        let path = UIBezierPath(ovalIn: bounds).cgPath
        halo.path = path
        outline.path = path
        isHidden = false
        CATransaction.commit()
    }

    func hide() {
        isHidden = true
    }
}

/// Takes the eraser's touch on the canvas from the moment it lands, so that erasing starts at once.
///
/// One pencil or finger erases. A second finger hands the touch over to scrolling and zooming; while a
/// pencil erases, a resting hand does nothing.
final class EraserGestureRecognizer: UIGestureRecognizer {
    private var eraser: UITouch?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let eraser {
            if eraser.type == .direct {
                state = .cancelled
            } else {
                touches.forEach { ignore($0, for: event) }
            }
            return
        }
        guard touches.count == 1, let touch = touches.first else {
            state = .failed
            return
        }
        eraser = touch
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let eraser, touches.contains(eraser) {
            state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let eraser, touches.contains(eraser) {
            state = .ended
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if let eraser, touches.contains(eraser) {
            state = .cancelled
        }
    }

    override func reset() {
        eraser = nil
    }
}

/// The strokes of the canvas while the eraser is down, ready to be erased.
///
/// The eraser works on the points that make up each stroke's path, which `StrokePoints` has mostly read
/// ahead. The pieces it leaves are made of the same points, so they keep the stroke's shape exactly. A
/// quick sweep across much ink therefore costs little more than looking at the ink it passes.
struct InkEraser {
    private struct Entry {
        var stroke: PKStroke
        /// Where the stroke's ink lies, in the coordinates of the drawing.
        var bounds: CGRect
        var samples: Samples?
    }

    private struct Samples {
        var points: [PKStrokePoint]
        var line: [StrokeEraser.LinePoint]
    }

    private var entries: [Entry]
    private let points: StrokePoints

    init(strokes: [PKStroke], points: StrokePoints) {
        entries = strokes.map { Entry(stroke: $0, bounds: $0.renderBounds) }
        self.points = points
    }

    var strokes: [PKStroke] { entries.map(\.stroke) }

    /// Erases what an eraser of `radius` covers on its way from `start` to `end`, in the coordinates of
    /// the drawing. A stroke it touches loses the piece under it and an eighth of `radius` beyond on
    /// either side, so that a pass across a line cuts about the eraser's diameter out of it and a light
    /// touch still leaves a visible gap.
    ///
    /// - Returns: Whether anything was erased.
    mutating func erase(from start: CGPoint, to end: CGPoint, radius: CGFloat) -> Bool {
        let sweep = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).insetBy(dx: -radius, dy: -radius)
        var hasErased = false
        var remaining: [Entry] = []
        remaining.reserveCapacity(entries.count)
        for var entry in entries {
            guard entry.bounds.intersects(sweep) else {
                remaining.append(entry)
                continue
            }
            let samples = entry.samples ?? Self.samples(of: entry.stroke, path: points.path(of: entry.stroke))
            guard let runs = StrokeEraser.remainingRuns(
                of: samples.line, sweptFrom: start, to: end, radius: radius, margin: radius / 8
            ) else {
                entry.samples = samples
                remaining.append(entry)
                continue
            }
            hasErased = true
            for run in runs {
                let piece = Self.piece(of: entry.stroke, samples: samples, run: run)
                if let samples = piece.samples {
                    points.remember(
                        StrokePoints.Path(points: samples.points, isShown: samples.line.map(\.isErasable)),
                        of: piece.stroke
                    )
                }
                remaining.append(piece)
            }
        }
        entries = remaining
        return hasErased
    }

    private static func samples(of stroke: PKStroke, path: StrokePoints.Path) -> Samples {
        let scale = hypot(stroke.transform.a, stroke.transform.b)
        let line = zip(path.points, path.isShown).map { point, isShown in
            StrokeEraser.LinePoint(
                location: point.location.applying(stroke.transform),
                reach: inkReach(of: point) * scale,
                isErasable: isShown
            )
        }
        return Samples(points: path.points, line: line)
    }

    /// How far a line's ink reaches from a point of its path, in the coordinates of the path.
    ///
    /// The size PencilKit keeps for a point is not the width of the line there: pen and monoline ink
    /// are drawn twice as wide as the size exceeds two.
    private static func inkReach(of point: PKStrokePoint) -> CGFloat {
        max(max(point.size.width, point.size.height) - 2, 0)
    }

    private static func piece(of stroke: PKStroke, samples: Samples, run: Range<Int>) -> Entry {
        let path = PKStrokePath(controlPoints: samples.points[run], creationDate: stroke.path.creationDate)
        let piece = PKStroke(ink: stroke.ink, path: path, transform: stroke.transform, mask: stroke.mask, randomSeed: stroke.randomSeed)
        let line = Array(samples.line[run])
        let bounds = line.reduce(CGRect.null) { bounds, point in
            bounds.union(CGRect(origin: point.location, size: .zero).insetBy(dx: -point.reach - 1, dy: -point.reach - 1))
        }
        return Entry(stroke: piece, bounds: bounds, samples: Samples(points: Array(samples.points[run]), line: line))
    }
}

/// The points of the strokes' paths, read ahead of the eraser.
///
/// PencilKit hands out the points of a path slowly, and a stroke cut at the edge of a page has a mask
/// that is slow to test them against: for a long stroke, either can take as long as a frame lasts, and
/// a quick sweep of the eraser reaches many strokes at once. While the eraser is chosen, the points of
/// the strokes on the canvas are therefore read in the background and kept per stroke.
final class StrokePoints {
    struct Path: Sendable {
        var points: [PKStrokePoint]
        /// Whether the stroke's mask lets each point show.
        var isShown: [Bool]
    }

    private var pathsByStroke: [UUID: Path] = [:]
    private var reading: Task<Void, Never>?

    /// The points of the stroke's path, read now if they have not been read yet.
    func path(of stroke: PKStroke) -> Path {
        if let path = pathsByStroke[stroke.id] { return path }
        let path = Self.read(stroke)
        pathsByStroke[stroke.id] = path
        return path
    }

    func remember(_ path: Path, of stroke: PKStroke) {
        pathsByStroke[stroke.id] = path
    }

    /// Reads the points of `strokes` in the background and forgets those of other strokes.
    func prepare(for strokes: [PKStroke]) {
        let ids = Set(strokes.map(\.id))
        pathsByStroke = pathsByStroke.filter { ids.contains($0.key) }
        let unread = strokes.filter { pathsByStroke[$0.id] == nil }
        reading?.cancel()
        guard !unread.isEmpty else { return }
        reading = Task { [weak self] in
            for start in stride(from: 0, to: unread.count, by: 16) {
                let read = await Self.read(Array(unread[start..<min(start + 16, unread.count)]))
                guard !Task.isCancelled, let self else { return }
                for (id, path) in read where pathsByStroke[id] == nil {
                    pathsByStroke[id] = path
                }
            }
        }
    }

    @concurrent
    private nonisolated static func read(_ strokes: [PKStroke]) async -> [(UUID, Path)] {
        strokes.map { ($0.id, read($0)) }
    }

    private nonisolated static func read(_ stroke: PKStroke) -> Path {
        let points = Array(stroke.path)
        let mask = stroke.mask?.cgPath
        return Path(points: points, isShown: points.map { mask?.contains($0.location) ?? true })
    }
}
