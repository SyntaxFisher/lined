import Foundation
import LinedModel

/// The directory of notebook packages, one per notebook, named by notebook identifier.
public struct NotebookPackageStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func package(for id: Notebook.ID) -> NotebookPackage {
        NotebookPackage(url: directory.appending(path: "\(id).\(NotebookPackage.pathExtension)", directoryHint: .isDirectory))
    }

    /// Writes a complete package and moves it into place in one step, so a failed or interrupted
    /// creation never leaves a partial notebook behind. `pdfSources` are copied into the package.
    @discardableResult
    public func createPackage(
        for id: Notebook.ID,
        document: NotebookDocument,
        pdfSources: [PDFSource.ID: URL] = [:]
    ) throws -> NotebookPackage {
        let fileManager = FileManager.default
        let destination = package(for: id)
        guard !fileManager.itemExists(at: destination.url) else { throw StorageError.notebookAlreadyExists }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let staging = try fileManager.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: directory, create: true
        )
        defer { try? fileManager.removeItem(at: staging) }

        let draft = NotebookPackage(url: staging.appending(path: destination.url.lastPathComponent, directoryHint: .isDirectory))
        try draft.createDirectories()
        for (sourceID, sourceURL) in pdfSources {
            try fileManager.copyItem(at: sourceURL, to: draft.pdfSourceURL(sourceID))
        }
        try draft.writeDocument(document)
        try fileManager.moveItem(at: draft.url, to: destination.url)
        return destination
    }

    public func deletePackage(for id: Notebook.ID) throws {
        let url = package(for: id).url
        guard FileManager.default.itemExists(at: url) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func storedNotebookIDs() throws -> Set<Notebook.ID> {
        guard FileManager.default.itemExists(at: directory) else { return [] }
        let packages = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return Set(packages.compactMap { url in
            guard url.pathExtension == NotebookPackage.pathExtension else { return nil }
            return UUID(uuidString: url.deletingPathExtension().lastPathComponent).map(Notebook.ID.init)
        })
    }
}
