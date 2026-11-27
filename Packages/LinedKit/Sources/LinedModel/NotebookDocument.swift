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
        NotebookDocument(pages: Page.pages(of: source, sizes: pageSizes))
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
        insert([page], at: index)
    }

    /// Inserts the pages in their order at `index`, clamped to the valid range.
    public mutating func insert(_ newPages: [Page], at index: Int) {
        pages.insert(contentsOf: newPages, at: min(max(index, 0), pages.count))
    }

    /// Moves the pages, keeping their order among themselves, in front of `successor` or to the end
    /// when it is `nil`. A successor that moves too gives way to the first page after it that stays.
    public mutating func movePages(_ pageIDs: [Page.ID], before successor: Page.ID?) {
        let moving = Set(pageIDs)
        let moved = pages.filter { moving.contains($0.id) }
        var remaining = pages.filter { !moving.contains($0.id) }
        let anchor = successor.flatMap(index(of:)).flatMap { start in
            pages[start...].first { !moving.contains($0.id) }?.id
        }
        let destination = anchor.flatMap { id in remaining.firstIndex { $0.id == id } } ?? remaining.count
        remaining.insert(contentsOf: moved, at: destination)
        pages = remaining
    }

    @discardableResult
    public mutating func removePage(_ pageID: Page.ID) throws(NotebookDocumentError) -> Page {
        guard let index = index(of: pageID) else { throw .pageNotFound }
        guard pages.count > 1 else { throw .cannotRemoveLastPage }
        return pages.remove(at: index)
    }
}
