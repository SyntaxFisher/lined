import LinedModel
import LinedRendering
import LinedStorage
import Observation
import PencilKit
import UIKit

/// An open notebook: its pages, their ink, and the undo history across them.
@Observable
final class NotebookSession {
    let notebookID: Notebook.ID
    private(set) var document: NotebookDocument
    private(set) var currentPageIndex: Int
    private(set) var canUndo = false
    private(set) var canRedo = false
    /// Counts the changes to each page's ink, so that pictures of a page know when they are outdated.
    private(set) var inkRevisions: [Page.ID: Int] = [:]
    var failureMessage: String?

    /// One history for the whole notebook. The canvases record their steps in it, and the tool picker,
    /// the undo gestures and the keyboard act on it, all by way of the responder chain.
    @ObservationIgnored let undoManager = UndoManager()

    @ObservationIgnored private let files: NotebookFiles
    @ObservationIgnored private let ink: PageInkStore
    @ObservationIgnored private let pdfSources: [PDFSource.ID: PDFDocumentSource]
    @ObservationIgnored private let onContentChange: () -> Void
    @ObservationIgnored private let thumbnails = NSCache<NSString, CGImage>()
    @ObservationIgnored private weak var canvas: (any PagedCanvasControlling)?
    @ObservationIgnored private var undoObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var savedViewState: NotebookViewState

    var pages: [Page] { document.pages }

    var currentPage: Page { pages[min(currentPageIndex, pages.count - 1)] }

    /// - Parameter onContentChange: Called whenever a change to the notebook has reached the disk.
    static func open(
        _ notebookID: Notebook.ID,
        in packages: NotebookPackageStore,
        onContentChange: @escaping () -> Void
    ) async throws -> NotebookSession {
        let files = NotebookFiles(package: packages.package(for: notebookID))
        let document = try await files.readDocument()
        return NotebookSession(
            notebookID: notebookID,
            document: document,
            viewState: await files.readViewState(),
            pdfSources: await files.openPDFSources(of: document),
            files: files,
            onContentChange: onContentChange
        )
    }

    private init(
        notebookID: Notebook.ID,
        document: NotebookDocument,
        viewState: NotebookViewState,
        pdfSources: [PDFSource.ID: PDFDocumentSource],
        files: NotebookFiles,
        onContentChange: @escaping () -> Void
    ) {
        self.notebookID = notebookID
        self.document = document
        self.pdfSources = pdfSources
        self.files = files
        self.onContentChange = onContentChange
        savedViewState = viewState
        currentPageIndex = viewState.lastViewedPageID.flatMap(document.index(of:)) ?? 0
        ink = PageInkStore(files: files)
        ink.onSave = onContentChange
        ink.onSaveFailure = { [weak self] error in
            self?.failureMessage = ErrorMessage.text(for: error)
        }
        observeUndoManager()
    }

    isolated deinit {
        undoObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Connects the canvas that shows this notebook and opens it where the reader left off.
    func attach(_ canvas: any PagedCanvasControlling) {
        self.canvas = canvas
        canvas.setPages(pages)
        canvas.scroll(to: currentPage.id, animated: false)
    }

    func showPage(_ pageID: Page.ID) {
        canvas?.scroll(to: pageID, animated: false)
    }

    /// Brings the disk up to date with the ink and the place the reader is at.
    func save() async {
        await ink.save()
        let viewState = NotebookViewState(lastViewedPageID: currentPage.id)
        guard viewState != savedViewState else { return }
        savedViewState = viewState
        await files.writeViewState(viewState)
    }

    // MARK: Pages

    /// Adds a page after the current one, on the given paper or else on the current page's paper.
    func addPage(template: PaperTemplate? = nil) async {
        let page = currentPage.successor(template: template)
        var updated = document
        updated.insert(page, at: min(currentPageIndex, pages.count - 1) + 1)
        await apply(updated)
        canvas?.scroll(to: page.id, animated: true)
    }

    func deletePage(_ pageID: Page.ID) async {
        var updated = document
        guard (try? updated.removePage(pageID)) != nil else { return }
        ink.discard(pageID)
        await apply(updated)
        try? await files.removeUnreferencedResources(keeping: updated)
    }

    private func apply(_ updated: NotebookDocument) async {
        document = updated
        currentPageIndex = min(currentPageIndex, updated.pages.count - 1)
        canvas?.setPages(updated.pages)
        do {
            try await files.writeDocument(updated)
            onContentChange()
        } catch {
            failureMessage = ErrorMessage.text(for: error)
        }
    }

    // MARK: Undo

    private func observeUndoManager() {
        let changes: [Notification.Name] = [.NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange]
        undoObservers = changes.map { name in
            NotificationCenter.default.addObserver(forName: name, object: undoManager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshUndoAvailability() }
            }
        }
    }

    private func refreshUndoAvailability() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }

    // MARK: Thumbnails

    func thumbnail(for page: Page) async -> CGImage? {
        let key = "\(page.id)#\(inkRevisions[page.id, default: 0])" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let image = await PageThumbnailRenderer.image(
            pageSize: page.size.cgSize,
            background: backgroundRenderer(for: page),
            drawing: await ink.drawing(for: page.id),
            maxPixelLength: 480
        )
        if let image {
            thumbnails.setObject(image, forKey: key)
        }
        return image
    }
}

extension NotebookSession: PagedCanvasDelegate {
    func backgroundRenderer(for page: Page) -> any PageBackgroundRenderer {
        page.backgroundRenderer { pdfSources[$0] }
    }

    func drawing(for pageID: Page.ID) async -> PKDrawing {
        await ink.beginDisplaying(pageID)
    }

    func canvasDidChangeDrawing(_ drawing: PKDrawing, on pageID: Page.ID) {
        ink.setDrawing(drawing, for: pageID)
        inkRevisions[pageID, default: 0] += 1
        // An undone or redone stroke may lie on a page that is out of sight.
        if undoManager.isUndoing || undoManager.isRedoing {
            canvas?.reveal(pageID)
        }
    }

    func canvasDidEndDisplayingPage(_ pageID: Page.ID) {
        ink.endDisplaying(pageID)
    }

    func canvasDidShowPage(at index: Int) {
        currentPageIndex = index
    }

    func canvasDidChangeUndoHistory() {
        refreshUndoAvailability()
    }
}
