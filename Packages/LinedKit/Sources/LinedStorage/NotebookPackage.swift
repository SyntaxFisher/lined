import Foundation
import LinedModel

/// One notebook on disk: a directory holding the page list, one drawing file per page and the imported PDFs.
///
///     <notebook-id>.lined/
///       notebook.json            page list
///       view-state.json          reading position
///       drawings/<page-id>.drawing
///       sources/<source-id>.pdf
///
/// Drawings are opaque data to this module; the app decides their encoding.
public struct NotebookPackage: Equatable, Sendable {
    public static let pathExtension = "lined"

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    // MARK: Document

    public func readDocument() throws -> NotebookDocument {
        let file = try VersionedJSON.read(NotebookFile.self, from: documentURL)
        guard let document = NotebookDocument(pages: file.pages) else { throw StorageError.corruptFile(documentURL) }
        return document
    }

    public func writeDocument(_ document: NotebookDocument) throws {
        try VersionedJSON.write(NotebookFile(pages: document.pages), to: documentURL)
    }

    // MARK: Drawings

    public func readDrawing(for pageID: Page.ID) throws -> Data? {
        let url = drawingURL(for: pageID)
        guard FileManager.default.itemExists(at: url) else { return nil }
        return try Data(contentsOf: url)
    }

    /// Stores the page's drawing; `nil` removes it.
    public func writeDrawing(_ data: Data?, for pageID: Page.ID) throws {
        let url = drawingURL(for: pageID)
        if let data {
            try data.write(to: url, options: .atomic)
        } else if FileManager.default.itemExists(at: url) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Moves a drawing that cannot be decoded aside, so later edits to the page do not overwrite it.
    public func quarantineDrawing(for pageID: Page.ID) throws {
        let url = drawingURL(for: pageID)
        let destination = url.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: url, to: destination)
    }

    // MARK: PDF sources

    public func pdfSourceURL(_ id: PDFSource.ID) -> URL {
        sourcesDirectory.appending(path: "\(id).pdf", directoryHint: .notDirectory)
    }

    /// Copies a PDF into the package under a new identifier. The copy appears under its final name
    /// only once it is complete. Until a page refers to it, housekeeping may remove it again.
    public func addPDFSource(copying url: URL) throws -> PDFSource.ID {
        let id = PDFSource.ID()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)
        let partial = sourcesDirectory.appending(path: "\(id).partial", directoryHint: .notDirectory)
        defer { try? fileManager.removeItem(at: partial) }
        try fileManager.copyItem(at: url, to: partial)
        try fileManager.moveItem(at: partial, to: pdfSourceURL(id))
        return id
    }

    // MARK: View state

    /// The stored reading position, or the default when none was stored or it cannot be read.
    public func readViewState() -> NotebookViewState {
        guard let data = try? Data(contentsOf: viewStateURL) else { return NotebookViewState() }
        return (try? JSONDecoder().decode(NotebookViewState.self, from: data)) ?? NotebookViewState()
    }

    public func writeViewState(_ state: NotebookViewState) throws {
        try JSONEncoder().encode(state).write(to: viewStateURL, options: .atomic)
    }

    // MARK: Housekeeping

    /// Deletes drawings of pages and PDF sources that `document` no longer refers to.
    public func removeUnreferencedResources(keeping document: NotebookDocument) throws {
        let pageIDs = Set(document.pages.map(\.id.rawValue))
        let sourceIDs = Set(document.referencedPDFSources.map(\.rawValue))
        try removeFiles(in: drawingsDirectory, withExtension: "drawing", keeping: pageIDs)
        try removeFiles(in: sourcesDirectory, withExtension: "pdf", keeping: sourceIDs)
    }

    func createDirectories() throws {
        for directory in [drawingsDirectory, sourcesDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func removeFiles(in directory: URL, withExtension pathExtension: String, keeping identifiers: Set<UUID>) throws {
        let fileManager = FileManager.default
        for file in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where file.pathExtension == pathExtension {
            guard let identifier = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
            if !identifiers.contains(identifier) {
                try fileManager.removeItem(at: file)
            }
        }
    }

    private var documentURL: URL { url.appending(path: "notebook.json", directoryHint: .notDirectory) }
    private var viewStateURL: URL { url.appending(path: "view-state.json", directoryHint: .notDirectory) }
    private var drawingsDirectory: URL { url.appending(path: "drawings", directoryHint: .isDirectory) }
    private var sourcesDirectory: URL { url.appending(path: "sources", directoryHint: .isDirectory) }

    private func drawingURL(for pageID: Page.ID) -> URL {
        drawingsDirectory.appending(path: "\(pageID).drawing", directoryHint: .notDirectory)
    }
}

private struct NotebookFile: VersionedFile {
    static let currentFormatVersion = 1

    var formatVersion = NotebookFile.currentFormatVersion
    var pages: [Page]
}
