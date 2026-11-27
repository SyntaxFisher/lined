import LinedInk
import LinedModel
import PencilKit

/// A change to a page's ink as PencilKit draws it.
typealias PageInkChange = InkChange<Page.ID, PKStroke>

nonisolated extension PKStroke: @retroactive InkStroke {
    public var start: CGPoint {
        guard let mask else {
            return path.first?.location.applying(transform) ?? renderBounds.origin
        }
        let visible = path.first { mask.contains($0.location) }?.location ?? CGPoint(x: mask.bounds.midX, y: mask.bounds.midY)
        return visible.applying(transform)
    }

    public var bounds: CGRect { renderBounds }

    public func applying(_ transform: CGAffineTransform) -> PKStroke {
        var stroke = self
        stroke.transform = self.transform.concatenating(transform)
        return stroke
    }

    /// A stroke is cut with its mask, which PencilKit keeps in the coordinates of the stroke's path.
    /// The rest of the stroke still has the whole path, and starts where its path enters the mask.
    ///
    /// The cut stroke is a new stroke with an identity of its own: a canvas draws a stroke it
    /// already shows again only when the stroke's identity changes.
    public func clipped(to rect: CGRect) -> PKStroke? {
        guard draws(in: rect) else { return nil }
        let page = UIBezierPath(rect: rect)
        page.apply(transform.inverted())
        var clip = page.cgPath.intersection(lineArea)
        if let mask {
            clip = clip.intersection(mask.cgPath)
        }
        guard !clip.isEmpty else { return nil }
        return PKStroke(ink: ink, path: path, transform: transform, mask: UIBezierPath(cgPath: clip), randomSeed: randomSeed)
    }

    /// The area the line of the stroke covers, with room to spare, in the coordinates of its path.
    private var lineArea: CGPath {
        let points = Array(path.interpolatedPoints(by: .distance(2)))
        let width = points.map { max($0.size.width, $0.size.height) }.max() ?? 0
        let line = CGMutablePath()
        line.addLines(between: points.map(\.location))
        if let only = points.first, points.count == 1 {
            line.addLine(to: CGPoint(x: only.location.x + 0.01, y: only.location.y))
        }
        return line.copy(strokingWithWidth: width * 2 + 4, lineCap: .round, lineJoin: .round, miterLimit: 1)
    }

    /// Whether the line of the stroke comes within its own width of `rect`.
    private func draws(in rect: CGRect) -> Bool {
        path.interpolatedPoints(by: .distance(2)).contains { point in
            let reach = max(point.size.width, point.size.height) / 2
            return rect.insetBy(dx: -reach, dy: -reach).contains(point.location.applying(transform))
        }
    }

    /// What remains of the stroke after an eraser of `radius` swept from `start` to `end`, in the
    /// coordinates of the drawing, or `nil` when the eraser did not touch the stroke.
    ///
    /// The eraser takes the whole width of the line where it touches it, so the remaining pieces end
    /// as cleanly as the line's own ends. Each piece is a new stroke with the same ink, transform and mask.
    func erased(sweptFrom start: CGPoint, to end: CGPoint, radius: CGFloat) -> [PKStroke]? {
        let sweep = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).insetBy(dx: -radius, dy: -radius)
        guard renderBounds.intersects(sweep) else { return nil }
        let points = Array(path.interpolatedPoints(by: .distance(1)))
        let scale = hypot(transform.a, transform.b)
        let line = points.map { point in
            StrokeEraser.LinePoint(
                location: point.location.applying(transform),
                reach: max(point.size.width, point.size.height) / 2 * scale,
                isErasable: mask?.contains(point.location) ?? true
            )
        }
        guard let runs = StrokeEraser.remainingRuns(of: line, sweptFrom: start, to: end, radius: radius) else { return nil }
        return runs.map { run in
            let piece = PKStrokePath(controlPoints: points[run], creationDate: path.creationDate)
            return PKStroke(ink: ink, path: piece, transform: transform, mask: mask, randomSeed: randomSeed)
        }
    }

    public func fingerprint(into hasher: inout Hasher, onPage page: CGAffineTransform) {
        let transformOnPage = transform.concatenating(page.inverted())
        hasher.combine(id)
        hasher.combine(path.count)
        hasher.combine(ink.inkType.rawValue)
        hasher.combine(ink.color.cgColor.components)
        for point in [path.first, path.last] {
            guard let point else { continue }
            InkFingerprint.combine(point.location.applying(transformOnPage), into: &hasher)
        }
        for value in [transformOnPage.a, transformOnPage.b, transformOnPage.c, transformOnPage.d] {
            hasher.combine((value * 1_000_000).rounded())
        }
        // A stroke cut at the edge of a page keeps its path and differs in its mask.
        mask?.cgPath.applyWithBlock { element in
            let pointCount = switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: 1
            case .addQuadCurveToPoint: 2
            case .addCurveToPoint: 3
            default: 0
            }
            hasher.combine(element.pointee.type.rawValue)
            for index in 0..<pointCount {
                InkFingerprint.combine(element.pointee.points[index], into: &hasher)
            }
        }
    }
}

extension ToolSettings {
    /// The tool as PencilKit applies it on a canvas that draws in document points, or `nil` for the
    /// eraser, which the canvas works itself.
    ///
    /// - Parameter documentScale: Document points per page point. The settings give widths in page points.
    func pencilKitTool(documentScale: CGFloat) -> (any PKTool)? {
        switch tool {
        case .pen:
            PKInkingTool(
                .monoline,
                color: penColor.uiColor,
                width: PKInkingTool.InkType.monoline.validWidthRange.clamping(penLineWidth * documentScale)
            )
        case .eraser:
            nil
        case .lasso:
            PKLassoTool()
        }
    }
}

extension InkColor {
    var uiColor: UIColor {
        let (red, green, blue) = components
        return UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

private extension ClosedRange<CGFloat> {
    func clamping(_ value: Double) -> CGFloat {
        Swift.min(Swift.max(CGFloat(value), lowerBound), upperBound)
    }
}
