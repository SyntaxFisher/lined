import Foundation
import LinedModel
import LinedStorage
import Observation

/// The app's long-lived services, created once at launch.
@Observable
final class AppEnvironment {
    let library: LibraryModel
    let covers: CoverStore
    private let packages: NotebookPackageStore

    convenience init() throws {
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try self.init(
            location: .applicationSupport(),
            coverDirectory: caches.appending(path: "Covers", directoryHint: .isDirectory)
        )
    }

    init(location: StorageLocation, coverDirectory: URL) throws {
        let index = LibraryIndexStore(fileURL: location.libraryIndex)
        packages = NotebookPackageStore(directory: location.notebooks)
        covers = CoverStore(directory: coverDirectory, packages: packages)
        library = LibraryModel(
            library: try Self.loadLibrary(from: index, packages: packages),
            index: index,
            packages: packages
        )
        let notebooks = Set(library.library.notebooks.map(\.id))
        Task { [covers] in await covers.removeCovers(keeping: notebooks) }
    }

    func openNotebook(_ id: Notebook.ID) async throws -> NotebookSession {
        try await NotebookSession.open(id, in: packages) { [library] in
            library.markNotebookModified(id)
        }
    }

    /// Loads the catalog and aligns it with the notebooks on disk. An unreadable catalog is set aside
    /// and rebuilt from the notebook packages, which keeps the notebooks at the cost of their folders.
    private static func loadLibrary(from index: LibraryIndexStore, packages: NotebookPackageStore) throws -> Library {
        var library: Library
        do {
            library = try index.load()
        } catch StorageError.corruptFile {
            try index.quarantine()
            library = Library()
        }
        let recoveredTitle = String(localized: "Recovered Notebook")
        if library.reconcile(storedNotebooks: try packages.storedNotebookIDs(), recoveredTitle: recoveredTitle) {
            try index.save(library)
        }
        return library
    }
}
