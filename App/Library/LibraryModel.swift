import Foundation
import LinedModel
import LinedRendering
import LinedStorage
import Observation

/// The library as the interface sees it. Every change is written to disk before it becomes visible.
@Observable
final class LibraryModel {
    private(set) var library: Library
    var failureMessage: String?

    var sortOrder: LibrarySortOrder {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: Preference.librarySortOrder) }
    }

    @ObservationIgnored private let index: LibraryIndexStore
    @ObservationIgnored private let packages: NotebookPackageStore

    init(library: Library, index: LibraryIndexStore, packages: NotebookPackageStore) {
        self.library = library
        self.index = index
        self.packages = packages
        sortOrder = UserDefaults.standard.string(forKey: Preference.librarySortOrder).flatMap(LibrarySortOrder.init) ?? .dateModified
    }

    func contents(of folderID: Folder.ID?) -> [LibraryEntry] {
        library.contents(of: folderID, sortedBy: sortOrder)
    }

    /// Runs a change and shows its failure to the user instead of throwing it.
    func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            failureMessage = ErrorMessage.text(for: error)
        }
    }

    // MARK: Changes

    @discardableResult
    func createFolder(named name: String, in parentID: Folder.ID?) throws -> Folder {
        try update { try $0.createFolder(named: name, in: parentID) }
    }

    func rename(_ item: LibraryEntry.ID, to name: String) throws {
        try update { try $0.rename(item, to: name) }
    }

    func move(_ items: [LibraryEntry.ID], to destination: Folder.ID?) throws {
        try update { try $0.move(items, to: destination) }
    }

    /// Packages go first: a catalog entry without a package is dropped at the next launch,
    /// whereas a package without an entry would come back as a recovered notebook.
    func delete(_ items: [LibraryEntry.ID]) throws {
        var draft = library
        let removedNotebooks = try draft.delete(items)
        for id in removedNotebooks {
            try packages.deletePackage(for: id)
        }
        try index.save(draft)
        library = draft
    }

    func markNotebookModified(_ id: Notebook.ID) {
        perform { try update { $0.markNotebookModified(id) } }
    }

    func createNotebook(
        titled title: String,
        template: PaperTemplate,
        pageSize: PageSize,
        in folderID: Folder.ID?
    ) async throws -> Notebook {
        let id = Notebook.ID()
        try await NotebookFactory.createPaperNotebook(id, template: template, pageSize: pageSize, in: packages)
        return try register(id, titled: title, in: folderID)
    }

    /// Creates a notebook with one page per page of the PDF, titled after the file.
    func importPDF(from url: URL, into folderID: Folder.ID?) async throws -> Notebook {
        let id = Notebook.ID()
        try await NotebookFactory.importPDF(from: url, as: id, in: packages)
        return try register(id, titled: url.deletingPathExtension().lastPathComponent, in: folderID)
    }

    private func register(_ id: Notebook.ID, titled title: String, in folderID: Folder.ID?) throws -> Notebook {
        do {
            return try update { try $0.addNotebook(id: id, titled: title, in: folderID) }
        } catch {
            try? packages.deletePackage(for: id)
            throw error
        }
    }

    private func update<Result>(_ change: (inout Library) throws -> Result) throws -> Result {
        var draft = library
        let result = try change(&draft)
        try index.save(draft)
        library = draft
        return result
    }
}

/// Builds notebook packages off the main thread.
private nonisolated enum NotebookFactory {
    @concurrent
    static func createPaperNotebook(
        _ id: Notebook.ID,
        template: PaperTemplate,
        pageSize: PageSize,
        in packages: NotebookPackageStore
    ) async throws {
        try packages.createPackage(for: id, document: .paper(template, size: pageSize))
    }

    @concurrent
    static func importPDF(from url: URL, as id: Notebook.ID, in packages: NotebookPackageStore) async throws {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
        }
        let sourceID = PDFSource.ID()
        let pageSizes = try PDFDocumentSource(url: url).pageSizes
        guard let document = NotebookDocument.pdf(source: sourceID, pageSizes: pageSizes) else {
            throw PDFSourceError.noPages
        }
        try packages.createPackage(for: id, document: document, pdfSources: [sourceID: url])
    }
}
