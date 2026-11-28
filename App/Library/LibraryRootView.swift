import LinedModel
import Observation
import SwiftUI

enum LibraryRoute: Hashable {
    case folder(Folder.ID)
    case notebook(Notebook.ID)
}

/// Where the reader is in the library: the folders they opened and, at most, one notebook on top.
@Observable
final class LibraryNavigator {
    var path: [LibraryRoute] = []

    func open(_ item: LibraryEntry) {
        switch item {
        case .folder(let folder): path.append(.folder(folder.id))
        case .notebook(let notebook): open(notebook.id)
        }
    }

    func open(_ notebookID: Notebook.ID) {
        path.append(.notebook(notebookID))
    }

    /// Opens the notebook in place of the one that is open, if any.
    func show(_ notebookID: Notebook.ID) {
        if openNotebookID != nil {
            path.removeLast()
        }
        path.append(.notebook(notebookID))
    }

    var openNotebookID: Notebook.ID? {
        if case .notebook(let id) = path.last { id } else { nil }
    }

    /// The innermost open folder, or `nil` for the library root.
    var currentFolderID: Folder.ID? {
        for case .folder(let id) in path.reversed() {
            return id
        }
        return nil
    }

    /// Shared PDFs the reader chose to add to the open notebook, waiting for it to take them.
    var pdfsForOpenNotebook: [URL] = []
}

struct LibraryRootView: View {
    @Environment(LibraryModel.self) private var library
    @State private var navigator = LibraryNavigator()

    var body: some View {
        @Bindable var library = library

        NavigationStack(path: $navigator.path) {
            FolderScreen(folderID: nil)
                .navigationDestination(for: LibraryRoute.self) { route in
                    switch route {
                    case .folder(let id): FolderScreen(folderID: id)
                    // A notebook that takes the place of another must not inherit its session.
                    case .notebook(let id): NotebookScreen(notebookID: id).id(id)
                    }
                }
        }
        .environment(navigator)
        .importsSharedPDFs(navigator: navigator)
        .alert("That didn't work", isPresented: $library.failureMessage.isPresent) {
            Button("OK") {}
        } message: {
            Text(library.failureMessage ?? "")
        }
    }
}
