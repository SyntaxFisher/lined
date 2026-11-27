import Foundation
import Testing
@testable import LinedModel

struct NotebookDocumentTests {
    @Test func paperNotebookStartsWithOnePage() {
        let size = PageSize.a4(.landscape)
        let document = NotebookDocument.paper(.squared, size: size)

        #expect(size == PageSize(width: 842, height: 595))
        #expect(document.pages.map(\.background) == [.paper(.squared)])
        #expect(document.referencedPDFSources.isEmpty)
    }

    @Test func pdfNotebookHasOnePagePerPDFPage() throws {
        let source = PDFSource.ID()
        let sizes = [PageSize(width: 400, height: 600), PageSize(width: 600, height: 400)]
        let document = try #require(NotebookDocument.pdf(source: source, pageSizes: sizes))

        #expect(document.pages.map(\.size) == sizes)
        #expect(document.pages.map(\.background) == [.pdf(source: source, pageIndex: 0), .pdf(source: source, pageIndex: 1)])
        #expect(document.referencedPDFSources == [source])
        #expect(NotebookDocument.pdf(source: source, pageSizes: []) == nil)
        #expect(NotebookDocument(pages: []) == nil)
    }

    @Test func insertsPagesAtClampedPositions() {
        var document = NotebookDocument.paper(.blank, size: PageSize.a4(.portrait))
        let first = document.pages[0]
        let appended = first.successor()
        let prepended = first.successor()

        document.insert(appended, at: 99)
        document.insert(prepended, at: -1)

        #expect(document.pages.map(\.id) == [prepended.id, first.id, appended.id])
        #expect(document.index(of: appended.id) == 2)
    }

    @Test func insertsThePagesOfAPDFInTheirOrder() {
        var document = NotebookDocument.paper(.blank, size: PageSize.a4(.portrait))
        let first = document.pages[0]
        document.insert(first.successor(), at: 1)
        let source = PDFSource.ID()
        let imported = Page.pages(of: source, sizes: [PageSize(width: 400, height: 600), PageSize(width: 600, height: 400)])

        document.insert(imported, at: 1)

        #expect(document.pages.map(\.id) == [first.id, imported[0].id, imported[1].id, document.pages[3].id])
        #expect(document.pages[1...2].map(\.background) == [.pdf(source: source, pageIndex: 0), .pdf(source: source, pageIndex: 1)])
        #expect(document.pages[2].size == PageSize(width: 600, height: 400))
        #expect(document.referencedPDFSources == [source])
    }

    @Test func movesPagesInFrontOfAnotherPageOrToTheEnd() {
        var document = NotebookDocument.paper(.blank, size: PageSize.a4(.portrait))
        for index in 1..<5 {
            document.insert(document.pages[0].successor(), at: index)
        }
        let ids = document.pages.map(\.id)

        document.movePages([ids[3]], before: ids[1])
        #expect(document.pages.map(\.id) == [ids[0], ids[3], ids[1], ids[2], ids[4]])

        document.movePages([ids[0]], before: nil)
        #expect(document.pages.map(\.id) == [ids[3], ids[1], ids[2], ids[4], ids[0]])

        document.movePages([ids[4], ids[1]], before: ids[3])
        #expect(document.pages.map(\.id) == [ids[1], ids[4], ids[3], ids[2], ids[0]])

        document.movePages([ids[2], ids[3]], before: ids[3])
        #expect(document.pages.map(\.id) == [ids[1], ids[4], ids[3], ids[2], ids[0]])

        document.movePages([Page.ID()], before: ids[1])
        #expect(document.pages.count == 5)
    }

    @Test func keepsAtLeastOnePage() throws {
        var document = NotebookDocument.paper(.blank, size: PageSize.a4(.portrait))
        let first = document.pages[0]
        let second = first.successor()
        document.insert(second, at: 1)

        #expect(throws: NotebookDocumentError.pageNotFound) { try document.removePage(Page.ID()) }
        #expect(try document.removePage(first.id) == first)
        #expect(throws: NotebookDocumentError.cannotRemoveLastPage) { try document.removePage(second.id) }
        #expect(document.pages == [second])
    }

    @Test func successorContinuesThePaperAndFollowsPDFPagesWithBlankPaper() {
        let size = PageSize(width: 500, height: 700)
        let lined = Page(size: size, background: .paper(.lined))
        let pdf = Page(size: size, background: .pdf(source: PDFSource.ID(), pageIndex: 4))

        #expect(lined.successor().background == .paper(.lined))
        #expect(lined.successor(template: .dotted).background == .paper(.dotted))
        #expect(pdf.successor().background == .paper(.blank))
        #expect(pdf.successor().size == size)
        #expect(lined.successor().id != lined.id)
    }

    @Test func pageBackgroundsHaveAStableJSONShape() throws {
        let source = PDFSource.ID(UUID(uuidString: "6F1E5F0C-4B0B-4F65-9A51-0A4D8C9E2B11")!)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let paper = try encoder.encode(PageBackground.paper(.lined))
        let pdf = try encoder.encode(PageBackground.pdf(source: source, pageIndex: 3))

        #expect(String(decoding: paper, as: UTF8.self) == #"{"kind":"paper","template":"lined"}"#)
        #expect(String(decoding: pdf, as: UTF8.self) == #"{"kind":"pdf","pageIndex":3,"source":"6F1E5F0C-4B0B-4F65-9A51-0A4D8C9E2B11"}"#)
        #expect(try JSONDecoder().decode(PageBackground.self, from: pdf) == .pdf(source: source, pageIndex: 3))
    }
}
