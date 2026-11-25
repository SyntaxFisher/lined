import LinedModel
import SwiftUI
import UniformTypeIdentifiers

/// The contents of one folder, or of the library root, as a grid of folders and notebook covers.
struct FolderScreen: View {
    let folderID: Folder.ID?

    @Environment(LibraryModel.self) private var library
    @Environment(LibraryNavigator.self) private var navigator
    @State private var namePrompt: NamePrompt?
    @State private var itemToMove: LibraryEntry?
    @State private var itemToDelete: LibraryEntry?
    @State private var isCreatingNotebook = false
    @State private var createdNotebook: Notebook?
    @State private var isChoosingPDF = false
    @State private var isImporting = false

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 28, alignment: .top)]

    var body: some View {
        @Bindable var library = library
        let items = library.contents(of: folderID)

        ScrollView {
            LazyVGrid(columns: columns, spacing: 32) {
                ForEach(items) { item in
                    Button {
                        navigator.open(item)
                    } label: {
                        LibraryEntryCell(item: item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { namePrompt = .rename(item, in: library) }
                        Button("Move", systemImage: "folder") { itemToMove = item }
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive) { itemToDelete = item }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    folderID == nil ? "No Notebooks" : "Empty Folder",
                    systemImage: "book.closed",
                    description: Text("Create a notebook or import a PDF with the plus button.")
                )
            } else if isImporting {
                ProgressView("Importing…")
                    .padding(24)
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu("Sort", systemImage: "arrow.up.arrow.down") {
                    Picker("Sort By", selection: $library.sortOrder) {
                        ForEach(LibrarySortOrder.allCases, id: \.self) { order in
                            Text(order.displayName).tag(order)
                        }
                    }
                }
                Menu("New", systemImage: "plus") {
                    Button("Notebook", systemImage: "book.closed") { isCreatingNotebook = true }
                    Button("Folder", systemImage: "folder.badge.plus") { namePrompt = .newFolder(in: folderID, of: library) }
                    Button("Import PDF", systemImage: "arrow.down.doc") { isChoosingPDF = true }
                }
            }
        }
        .namePrompt($namePrompt)
        .sheet(isPresented: $isCreatingNotebook, onDismiss: openCreatedNotebook) {
            NewNotebookSheet(folderID: folderID) { createdNotebook = $0 }
        }
        .sheet(item: $itemToMove) { item in
            MoveSheet(item: item)
        }
        .fileImporter(isPresented: $isChoosingPDF, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await importPDFs(urls) }
            }
        }
        .alert(deletionTitle, isPresented: isConfirmingDeletion, presenting: itemToDelete) { item in
            Button("Delete", role: .destructive) {
                library.perform { try library.delete(item.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            if case .folder = item {
                Text("The folder and everything in it will be deleted. This can't be undone.")
            } else {
                Text("This can't be undone.")
            }
        }
    }

    private var title: String {
        folderID.flatMap(library.library.folder)?.name ?? String(localized: "Library")
    }

    private var deletionTitle: String {
        String(localized: "Delete “\(itemToDelete?.name ?? "")”?")
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding {
            itemToDelete != nil
        } set: { isPresented in
            if !isPresented { itemToDelete = nil }
        }
    }

    /// Opens a new notebook once its sheet is gone; a push while the sheet is closing can get lost.
    private func openCreatedNotebook() {
        guard let notebook = createdNotebook else { return }
        createdNotebook = nil
        navigator.open(notebook.id)
    }

    /// Imports each PDF as its own notebook and opens the notebook when there is just one.
    private func importPDFs(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        var imported: [Notebook] = []
        for url in urls {
            do {
                imported.append(try await library.importPDF(from: url, into: folderID))
            } catch {
                library.failureMessage = ErrorMessage.text(for: error)
            }
        }
        if imported.count == 1, urls.count == 1 {
            navigator.open(imported[0].id)
        }
    }
}

private struct LibraryEntryCell: View {
    let item: LibraryEntry

    @Environment(LibraryModel.self) private var library

    var body: some View {
        VStack(spacing: 10) {
            picture
                .frame(height: 190, alignment: .bottom)
            VStack(spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                detail
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var picture: some View {
        switch item {
        case .folder:
            Image(systemName: "folder.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
        case .notebook(let notebook):
            NotebookCover(notebook: notebook)
        }
    }

    private var detail: Text {
        switch item {
        case .folder(let folder):
            Text("^[\(library.library.itemCount(in: folder.id)) item](inflect: true)")
        case .notebook(let notebook):
            Text(notebook.modifiedAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
        }
    }
}

private struct NotebookCover: View {
    let notebook: Notebook

    @Environment(AppEnvironment.self) private var environment
    @State private var image: CGImage?

    var body: some View {
        PagePicture(image: image, aspectRatio: image.map { CGFloat($0.width) / CGFloat($0.height) } ?? 0.71)
            .task(id: notebook.modifiedAt) {
                image = await environment.covers.cover(for: notebook)
            }
    }
}
