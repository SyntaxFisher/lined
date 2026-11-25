import CoreGraphics
import Foundation
import LinedModel
import PDFKit
import Testing
@testable import LinedRendering

struct PaperRenderingTests {
    private let pageSize = CGSize(width: 595, height: 842)

    private func render(_ template: PaperTemplate, region: CGRect? = nil, scale: CGFloat = 2) throws -> Bitmap {
        let renderer = PaperBackgroundRenderer(template: template)
        let region = region ?? CGRect(origin: .zero, size: pageSize)
        return Bitmap(try #require(PageRasterizer.image(of: renderer, pageSize: pageSize, region: region, scale: scale)))
    }

    @Test func blankPaperIsWhite() throws {
        let bitmap = try render(.blank, scale: 0.5)
        #expect(bitmap.colors.allSatisfy { $0 == .white })
    }

    @Test func linedPaperHasRulesAtTheLineSpacing() throws {
        let bitmap = try render(.lined)
        let firstLine = Int(Ruling.lineSpacing * 2.5 * 2)

        #expect(bitmap.width == 1190 && bitmap.height == 1684)
        #expect(bitmap.color(x: 600, y: firstLine) != .white)
        #expect(bitmap.color(x: 600, y: firstLine + Int(Ruling.lineSpacing * 2)) != .white)
        #expect(bitmap.color(x: 600, y: firstLine + Int(Ruling.lineSpacing)) == .white)
        #expect(bitmap.color(x: 600, y: 20) == .white)
    }

    @Test func squaredAndDottedPaperCoverThePage() throws {
        for template in [PaperTemplate.squared, .dotted] {
            let bitmap = try render(template)
            let inked = bitmap.colors.count { $0 != .white }
            #expect(inked > 1_000, "\(template)")
        }
    }

    @Test func aRegionMatchesTheSamePartOfTheWholePage() throws {
        let whole = try render(.squared)
        let part = try render(.squared, region: CGRect(x: 100, y: 200, width: 60, height: 40))

        #expect(part.width == 120 && part.height == 80)
        #expect(part.colors == whole.cropped(x: 200, y: 400, width: 120, height: 80))
    }
}

struct PDFRenderingTests {
    private let fixture: PDFFixture

    init() throws {
        fixture = try PDFFixture()
    }

    private func render(_ source: PDFDocumentSource, page index: Int, size: CGSize) throws -> Bitmap {
        let renderer = try #require(source.renderer(forPageAt: index))
        let region = CGRect(origin: .zero, size: size)
        return Bitmap(try #require(PageRasterizer.image(of: renderer, pageSize: size, region: region, scale: 1)))
    }

    @Test func readsPageSizes() throws {
        let source = try PDFDocumentSource(url: fixture.writeTwoPageDocument())

        #expect(source.pageCount == 2)
        #expect(source.pageSizes == [PageSize(width: 400, height: 600), PageSize(width: 600, height: 400)])
        #expect(source.renderer(forPageAt: 2) == nil)
    }

    @Test func drawsPagesTheRightWayUp() throws {
        let source = try PDFDocumentSource(url: fixture.writeTwoPageDocument())

        let first = try render(source, page: 0, size: CGSize(width: 400, height: 600))
        #expect(first.color(x: 50, y: 50) == .red)
        #expect(first.color(x: 350, y: 550) == .white)

        let second = try render(source, page: 1, size: CGSize(width: 600, height: 400))
        #expect(second.color(x: 550, y: 350) == .blue)
        #expect(second.color(x: 50, y: 50) == .white)
    }

    @Test func honoursPageRotation() throws {
        let document = try #require(PDFDocument(url: fixture.writeTwoPageDocument()))
        document.page(at: 0)?.rotation = 90
        let rotatedURL = fixture.url("rotated.pdf")
        #expect(document.write(to: rotatedURL))

        let source = try PDFDocumentSource(url: rotatedURL)
        let size = try #require(source.pageSizes.first)
        #expect(size == PageSize(width: 600, height: 400))

        let bitmap = try render(source, page: 0, size: size.cgSize)
        #expect(bitmap.color(x: 550, y: 50) == .red)
        #expect(bitmap.color(x: 50, y: 50) == .white)
    }

    @Test func rendersARegionAtHigherScale() throws {
        let source = try PDFDocumentSource(url: fixture.writeTwoPageDocument())
        let renderer = try #require(source.renderer(forPageAt: 0))
        let region = CGRect(x: 150, y: 250, width: 100, height: 100)

        let image = try #require(PageRasterizer.image(of: renderer, pageSize: CGSize(width: 400, height: 600), region: region, scale: 4))
        let bitmap = Bitmap(image)

        #expect(bitmap.width == 400 && bitmap.height == 400)
        #expect(bitmap.color(x: 100, y: 100) == .red)
        #expect(bitmap.color(x: 300, y: 100) == .white)
        #expect(bitmap.color(x: 100, y: 300) == .white)
    }

    @Test func resolvesPageBackgrounds() throws {
        let source = try PDFDocumentSource(url: fixture.writeTwoPageDocument())
        let sourceID = PDFSource.ID()
        let size = PageSize(width: 400, height: 600)
        let pdfPage = Page(size: size, background: .pdf(source: sourceID, pageIndex: 0))
        let paperPage = Page(size: size, background: .paper(.dotted))

        #expect(paperPage.backgroundRenderer { _ in nil } is PaperBackgroundRenderer)
        #expect(pdfPage.backgroundRenderer { $0 == sourceID ? source : nil } is PDFPageBackgroundRenderer)
        #expect((pdfPage.backgroundRenderer { _ in nil } as? PaperBackgroundRenderer)?.template == .blank)
    }

    @Test func rejectsFilesItCannotDisplay() throws {
        let garbage = fixture.url("garbage.pdf")
        try Data("not a pdf".utf8).write(to: garbage)

        #expect(throws: PDFSourceError.unreadable) { try PDFDocumentSource(url: garbage) }
        #expect(throws: PDFSourceError.unreadable) { try PDFDocumentSource(url: fixture.url("missing.pdf")) }
        #expect(throws: PDFSourceError.passwordProtected) {
            try PDFDocumentSource(url: fixture.writeTwoPageDocument(named: "locked.pdf", password: "secret"))
        }
    }
}
