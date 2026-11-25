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
                    case .notebook(let id): NotebookScreen(notebookID: id)
                    }
                }
        }
        .environment(navigator)
        .alert("That didn't work", isPresented: $library.failureMessage.isPresent) {
            Button("OK") {}
        } message: {
            Text(library.failureMessage ?? "")
        }
    }
}
