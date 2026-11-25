import CoreGraphics
import Foundation
import LinedModel

public enum PDFSourceError: Error, Equatable, Sendable {
    case unreadable
    case passwordProtected
    case noPages
}

/// A PDF file opened for display. Pages are addressed by zero-based index.
///
/// Core Graphics reads the file lazily and allows drawing its pages from several threads at once.
public final class PDFDocumentSource: @unchecked Sendable {
    private let document: CGPDFDocument

    public init(url: URL) throws(PDFSourceError) {
        guard let document = CGPDFDocument(url as CFURL) else { throw .unreadable }
        guard document.isUnlocked || document.unlockWithPassword("") else { throw .passwordProtected }
        guard document.numberOfPages > 0 else { throw .noPages }
        self.document = document
    }

    public var pageCount: Int { document.numberOfPages }

    /// The size each page is displayed at: its crop box, turned by the page's rotation.
    public var pageSizes: [PageSize] {
        (0..<pageCount).map { index in
            guard let page = document.page(at: index + 1) else { return PageSize(format: .a4, orientation: .portrait) }
            let size = PDFPageBackgroundRenderer.displaySize(of: page)
            return PageSize(width: size.width, height: size.height)
        }
    }

    public func renderer(forPageAt index: Int) -> (any PageBackgroundRenderer)? {
        document.page(at: index + 1).map(PDFPageBackgroundRenderer.init)
    }
}

struct PDFPageBackgroundRenderer: PageBackgroundRenderer, @unchecked Sendable {
    let page: CGPDFPage

    static func displaySize(of page: CGPDFPage) -> CGSize {
        let box = page.getBoxRect(.cropBox)
        let isSideways = page.rotationAngle % 180 != 0
        return isSideways ? CGSize(width: box.height, height: box.width) : box.size
    }

    func draw(in context: CGContext, pageSize: CGSize) {
        context.saveGState()
        defer { context.restoreGState() }
        // PDF space has its origin at the bottom-left corner.
        context.translateBy(x: 0, y: pageSize.height)
        context.scaleBy(x: 1, y: -1)
        let target = CGRect(origin: .zero, size: pageSize)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: target, rotate: 0, preserveAspectRatio: true))
        context.clip(to: page.getBoxRect(.cropBox))
        context.interpolationQuality = .high
        context.drawPDFPage(page)
    }
}
