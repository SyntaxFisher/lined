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

    public func moved(by offset: CGVector) -> PKStroke {
        var stroke = self
        stroke.transform = transform.concatenating(CGAffineTransform(translationX: offset.dx, y: offset.dy))
        return stroke
    }

    /// A stroke is cut with its mask, which PencilKit keeps in the coordinates of the stroke's path.
    /// The rest of the stroke still has the whole path, and starts where its path enters the mask.
    ///
    /// The mask hugs the line: the stroke eraser takes a stroke away wherever its mask is touched,
    /// so a mask in the shape of the whole page would let a tap anywhere on the page erase it.
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

    public func fingerprint(into hasher: inout Hasher, relativeTo origin: CGPoint) {
        hasher.combine(id)
        hasher.combine(path.count)
        hasher.combine(ink.inkType.rawValue)
        hasher.combine(ink.color.cgColor.components)
        for point in [path.first, path.last] {
            guard let point else { continue }
            InkFingerprint.combine(point.location.applying(transform), relativeTo: origin, into: &hasher)
        }
        for value in [transform.a, transform.b, transform.c, transform.d] {
            hasher.combine((value * 1_000_000).rounded())
        }
        // The precise eraser leaves a stroke's path alone and cuts into its mask.
        mask?.cgPath.applyWithBlock { element in
            let pointCount = switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: 1
            case .addQuadCurveToPoint: 2
            case .addCurveToPoint: 3
            default: 0
            }
            hasher.combine(element.pointee.type.rawValue)
            for index in 0..<pointCount {
                InkFingerprint.combine(element.pointee.points[index], relativeTo: .zero, into: &hasher)
            }
        }
    }
}

extension ToolSettings {
    /// The tool as PencilKit applies it. Widths are in page points, which is what the canvas draws in.
    var pencilKitTool: any PKTool {
        switch tool {
        case .pen:
            let ink: PKInkingTool.InkType = penStyle == .pen ? .pen : .monoline
            return PKInkingTool(ink, color: penColor.uiColor, width: ink.validWidthRange.clamping(penLineWidth))
        case .highlighter:
            return PKInkingTool(
                .marker,
                color: highlighterColor.uiColor,
                width: PKInkingTool.InkType.marker.validWidthRange.clamping(highlighterLineWidth)
            )
        case .eraser:
            return switch eraserMode {
            case .stroke: PKEraserTool(.vector)
            case .precise: PKEraserTool(.bitmap, width: ToolSettings.preciseEraserWidth)
            }
        case .lasso:
            return PKLassoTool()
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
