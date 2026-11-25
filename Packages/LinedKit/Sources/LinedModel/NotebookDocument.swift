import Foundation

public enum NotebookDocumentError: Error, Equatable, Sendable {
    case pageNotFound
    case cannotRemoveLastPage
}

/// The ordered pages of a notebook. A document always has at least one page.
public struct NotebookDocument: Equatable, Sendable {
    public private(set) var pages: [Page]

    /// Returns `nil` for an empty page list.
    public init?(pages: [Page]) {
        guard !pages.isEmpty else { return nil }
        self.pages = pages
    }

    public static func paper(_ template: PaperTemplate, size: PageSize) -> NotebookDocument {
        NotebookDocument(first: Page(size: size, background: .paper(template)))
    }

    /// One page per PDF page, in the PDF's order. Returns `nil` for a PDF without pages.
    public static func pdf(source: PDFSource.ID, pageSizes: [PageSize]) -> NotebookDocument? {
        NotebookDocument(pages: pageSizes.enumerated().map { index, size in
            Page(size: size, background: .pdf(source: source, pageIndex: index))
        })
    }

    private init(first page: Page) {
        pages = [page]
    }

    public func index(of pageID: Page.ID) -> Int? {
        pages.firstIndex { $0.id == pageID }
    }

    public var referencedPDFSources: Set<PDFSource.ID> {
        Set(pages.compactMap { page in
            if case .pdf(let source, _) = page.background { source } else { nil }
        })
    }

    /// Inserts the page at `index`, clamped to the valid range.
    public mutating func insert(_ page: Page, at index: Int) {
        pages.insert(page, at: min(max(index, 0), pages.count))
    }

    @discardableResult
    public mutating func removePage(_ pageID: Page.ID) throws(NotebookDocumentError) -> Page {
        guard let index = index(of: pageID) else { throw .pageNotFound }
        guard pages.count > 1 else { throw .cannotRemoveLastPage }
        return pages.remove(at: index)
    }
}
