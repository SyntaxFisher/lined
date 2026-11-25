import CoreGraphics
import LinedModel

/// Draws what lies beneath the ink of one page.
///
/// The context's coordinate space is the page in points with the origin at the top-left corner and y pointing down,
/// already scaled and clipped by the caller. Implementations must be safe to call from several threads at once.
public protocol PageBackgroundRenderer: Sendable {
    func draw(in context: CGContext, pageSize: CGSize)
}

extension PageSize {
    public var cgSize: CGSize { CGSize(width: width, height: height) }
}

public struct PaperBackgroundRenderer: PageBackgroundRenderer {
    public let template: PaperTemplate

    public init(template: PaperTemplate) {
        self.template = template
    }

    public func draw(in context: CGContext, pageSize: CGSize) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(Ruling.color)
        context.setFillColor(Ruling.color)
        context.setLineWidth(Ruling.lineWidth)

        switch template {
        case .blank:
            break
        case .lined:
            var y = Ruling.lineSpacing * 2.5
            while y < pageSize.height - Ruling.lineSpacing / 2 {
                context.move(to: CGPoint(x: 0, y: y))
                context.addLine(to: CGPoint(x: pageSize.width, y: y))
                y += Ruling.lineSpacing
            }
            context.strokePath()
        case .squared:
            for x in Ruling.gridPositions(along: pageSize.width) {
                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x, y: pageSize.height))
            }
            for y in Ruling.gridPositions(along: pageSize.height) {
                context.move(to: CGPoint(x: 0, y: y))
                context.addLine(to: CGPoint(x: pageSize.width, y: y))
            }
            context.strokePath()
        case .dotted:
            let radius = Ruling.dotRadius
            for y in Ruling.gridPositions(along: pageSize.height) {
                for x in Ruling.gridPositions(along: pageSize.width) {
                    context.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                }
            }
            context.fillPath()
        }
    }
}

/// Ruling geometry in points. The grid uses the common 5 mm pitch.
enum Ruling {
    static let color = CGColor(srgbRed: 0.70, green: 0.76, blue: 0.84, alpha: 1)
    static let lineWidth: CGFloat = 0.5
    static let lineSpacing: CGFloat = 24
    static let gridSpacing: CGFloat = 5 * 72 / 25.4
    static let dotRadius: CGFloat = 0.8

    /// Grid line positions centred on the given length, so the cut-off cells at both edges are equal.
    static func gridPositions(along length: CGFloat) -> [CGFloat] {
        let cells = (length / gridSpacing).rounded(.down)
        let inset = (length - cells * gridSpacing) / 2
        return (0...Int(cells)).map { inset + CGFloat($0) * gridSpacing }
    }
}

extension Page {
    /// The renderer for this page's background. A PDF page whose source is unavailable falls back
    /// to blank paper, so the page stays usable.
    public func backgroundRenderer(pdfSource: (PDFSource.ID) -> PDFDocumentSource?) -> any PageBackgroundRenderer {
        switch background {
        case .paper(let template):
            PaperBackgroundRenderer(template: template)
        case .pdf(let source, let pageIndex):
            pdfSource(source)?.renderer(forPageAt: pageIndex) ?? PaperBackgroundRenderer(template: .blank)
        }
    }
}
