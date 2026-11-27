import Foundation
import LinedModel
import Testing
@testable import LinedStorage

struct NotebookPackageTests {
    private let directory: TemporaryDirectory
    private let store: NotebookPackageStore
    private let a4 = PageSize.a4(.portrait)

    init() throws {
        directory = try TemporaryDirectory()
        store = NotebookPackageStore(directory: directory.url.appending(path: "Notebooks", directoryHint: .isDirectory))
    }

    @Test func createsAPackageThatReadsBackItsDocument() throws {
        let id = Notebook.ID()
        let document = NotebookDocument.paper(.lined, size: a4)

        let package = try store.createPackage(for: id, document: document)

        #expect(package.url.lastPathComponent == "\(id).lined")
        #expect(try package.readDocument() == document)
        #expect(try store.storedNotebookIDs() == [id])
        #expect(throws: StorageError.notebookAlreadyExists) { try store.createPackage(for: id, document: document) }
    }

    @Test func copiesImportedPDFsIntoThePackage() throws {
        let original = directory.file("lecture.pdf")
        try Data("%PDF-stub".utf8).write(to: original)
        let source = PDFSource.ID()
        let document = try #require(NotebookDocument.pdf(source: source, pageSizes: [a4, a4]))

        let package = try store.createPackage(for: Notebook.ID(), document: document, pdfSources: [source: original])

        #expect(try Data(contentsOf: package.pdfSourceURL(source)) == Data("%PDF-stub".utf8))
        #expect(FileManager.default.itemExists(at: original))
    }

    @Test func aFailedCreationLeavesNoPackageBehind() throws {
        let source = PDFSource.ID()
        let document = try #require(NotebookDocument.pdf(source: source, pageSizes: [a4]))

        #expect(throws: (any Error).self) {
            try store.createPackage(for: Notebook.ID(), document: document, pdfSources: [source: directory.file("missing.pdf")])
        }
        #expect(try store.storedNotebookIDs().isEmpty)
        #expect(directory.contents(of: store.directory).isEmpty)
    }

    @Test func deletesPackages() throws {
        let id = Notebook.ID()
        try store.createPackage(for: id, document: .paper(.blank, size: a4))

        try store.deletePackage(for: id)
        try store.deletePackage(for: id)

        #expect(try store.storedNotebookIDs().isEmpty)
    }

    @Test func storesOneDrawingPerPage() throws {
        let document = NotebookDocument.paper(.blank, size: a4)
        let pageID = document.pages[0].id
        let package = try store.createPackage(for: Notebook.ID(), document: document)

        #expect(try package.readDrawing(for: pageID) == nil)

        try package.writeDrawing(Data([1, 2, 3]), for: pageID)
        #expect(try package.readDrawing(for: pageID) == Data([1, 2, 3]))

        try package.writeDrawing(nil, for: pageID)
        try package.writeDrawing(nil, for: pageID)
        #expect(try package.readDrawing(for: pageID) == nil)
    }

    @Test func quarantinesAnUndecodableDrawing() throws {
        let document = NotebookDocument.paper(.blank, size: a4)
        let pageID = document.pages[0].id
        let package = try store.createPackage(for: Notebook.ID(), document: document)
        try package.writeDrawing(Data([0xFF]), for: pageID)

        try package.quarantineDrawing(for: pageID)

        #expect(try package.readDrawing(for: pageID) == nil)
        #expect(directory.contents(of: package.url.appending(path: "drawings")) == ["\(pageID).drawing.corrupt"])
    }

    @Test func remembersTheReadingPosition() throws {
        let document = NotebookDocument.paper(.blank, size: a4)
        let package = try store.createPackage(for: Notebook.ID(), document: document)

        #expect(package.readViewState() == NotebookViewState())

        let state = NotebookViewState(lastViewedPageID: document.pages[0].id)
        try package.writeViewState(state)
        #expect(package.readViewState() == state)
    }

    @Test func removesResourcesOfDeletedPages() throws {
        let original = directory.file("slides.pdf")
        try Data("%PDF-stub".utf8).write(to: original)
        let source = PDFSource.ID()
        var document = try #require(NotebookDocument.pdf(source: source, pageSizes: [a4]))
        let pdfPage = document.pages[0]
        let paperPage = pdfPage.successor()
        document.insert(paperPage, at: 1)
        let package = try store.createPackage(for: Notebook.ID(), document: document, pdfSources: [source: original])
        try package.writeDrawing(Data([1]), for: pdfPage.id)
        try package.writeDrawing(Data([2]), for: paperPage.id)

        try document.removePage(pdfPage.id)
        try package.writeDocument(document)
        try package.removeUnreferencedResources(keeping: document)

        #expect(try package.readDrawing(for: pdfPage.id) == nil)
        #expect(try package.readDrawing(for: paperPage.id) == Data([2]))
        #expect(!FileManager.default.itemExists(at: package.pdfSourceURL(source)))
    }

    @Test func refusesANotebookWrittenByANewerVersion() throws {
        let package = try store.createPackage(for: Notebook.ID(), document: .paper(.blank, size: a4))
        try Data(#"{"formatVersion": 2, "pages": []}"#.utf8).write(to: package.url.appending(path: "notebook.json"))

        #expect(throws: StorageError.unsupportedFormatVersion(found: 2, supported: 1)) { try package.readDocument() }
    }
}
