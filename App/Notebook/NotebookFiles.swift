import Foundation
import LinedModel
import LinedRendering
import LinedStorage
import PencilKit

/// All file access of one open notebook, off the main thread and in the order it was requested.
actor NotebookFiles {
    private let package: NotebookPackage

    init(package: NotebookPackage) {
        self.package = package
    }

    func readDocument() throws -> NotebookDocument {
        try package.readDocument()
    }

    func writeDocument(_ document: NotebookDocument) throws {
        try package.writeDocument(document)
    }

    func removeUnreferencedResources(keeping document: NotebookDocument) throws {
        try package.removeUnreferencedResources(keeping: document)
    }

    func readViewState() -> NotebookViewState {
        package.readViewState()
    }

    func writeViewState(_ state: NotebookViewState) {
        try? package.writeViewState(state)
    }

    /// Opens the PDFs the document's pages refer to. Sources that cannot be read are left out.
    func openPDFSources(of document: NotebookDocument) -> [PDFSource.ID: PDFDocumentSource] {
        var sources: [PDFSource.ID: PDFDocumentSource] = [:]
        for id in document.referencedPDFSources {
            sources[id] = try? PDFDocumentSource(url: package.pdfSourceURL(id))
        }
        return sources
    }

    /// Copies a PDF the user picked into the notebook and opens the copy. A PDF that cannot be shown
    /// is refused before anything is copied.
    func importPDF(from url: URL) throws -> (id: PDFSource.ID, source: PDFDocumentSource, pageSizes: [PageSize]) {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
        }
        _ = try PDFDocumentSource(url: url)
        let id = try package.addPDFSource(copying: url)
        let source = try PDFDocumentSource(url: package.pdfSourceURL(id))
        return (id, source, source.pageSizes)
    }

    /// The page's stored ink, or an empty drawing when the page has none. A drawing that cannot be
    /// decoded is moved aside rather than overwritten by the next save.
    func loadDrawing(for pageID: Page.ID) -> PKDrawing {
        guard let data = try? package.readDrawing(for: pageID) else { return PKDrawing() }
        if let drawing = try? PKDrawing(data: data) {
            return drawing
        }
        try? package.quarantineDrawing(for: pageID)
        return PKDrawing()
    }

    func saveDrawing(_ drawing: PKDrawing, for pageID: Page.ID) throws {
        try package.writeDrawing(drawing.strokes.isEmpty ? nil : drawing.dataRepresentation(), for: pageID)
    }
}
