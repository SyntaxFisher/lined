import LinedModel
import SwiftUI
import UniformTypeIdentifiers

/// The contents of one folder, or of the library root, as a grid of folders and notebook covers.
/// Items can be dragged onto folders, also several selected ones, and folders open while a drag is underway.
struct FolderScreen: View {
    let folderID: Folder.ID?

    @Environment(LibraryModel.self) private var library
    @Environment(LibraryNavigator.self) private var navigator
    @State private var namePrompt: NamePrompt?
    @State private var moveRequest: MoveRequest?
    @State private var itemsToDelete: [LibraryEntry] = []
    @State private var isCreatingNotebook = false
    @State private var createdNotebook: Notebook?
    @State private var isChoosingPDF = false
    @State private var isImporting = false
    @State private var isSelecting = false
    @State private var selection: Set<LibraryEntry.ID> = []
    @State private var isDragging = false
    @State private var dropTarget: Folder.ID?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 28, alignment: .top)]

    var body: some View {
        @Bindable var library = library
        let items = library.contents(of: folderID)

        ScrollView {
            LazyVGrid(columns: columns, spacing: 32) {
                ForEach(items) { item in
                    cell(for: item)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .dragContainer(for: LibraryDragItem.self) { ids in ids.map(LibraryDragItem.init) }
            .dragContainerSelection(isSelecting ? Array(selection) : [])
            .dragConfiguration(DragConfiguration(allowMove: true))
            .onDragSessionUpdated { session in
                switch session.phase {
                case .initial, .active: isDragging = true
                default: isDragging = false
                }
            }
        }
        .libraryDropDestination(folderID, isTargeted: .constant(false))
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
        .navigationBarBackButtonHidden(isSelecting)
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button(selection.count == items.count ? "Deselect All" : "Select All") {
                        selection = selection.count == items.count ? [] : Set(items.map(\.id))
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Move", systemImage: "folder") {
                        moveRequest = MoveRequest(items: selectedItems(in: items))
                    }
                    .disabled(selection.isEmpty)
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        itemsToDelete = selectedItems(in: items)
                    }
                    .disabled(selection.isEmpty)
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", role: .confirm) { endSelection() }
                }
            } else {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Sorting stays one long press away from selecting.
                    Menu("Select", systemImage: "checkmark.circle") {
                        Picker("Sort By", selection: $library.sortOrder) {
                            ForEach(LibrarySortOrder.allCases, id: \.self) { order in
                                Text(order.displayName).tag(order)
                            }
                        }
                    } primaryAction: {
                        isSelecting = true
                    }
                    Menu("New", systemImage: "plus") {
                        Button("Notebook", systemImage: "book.closed") { isCreatingNotebook = true }
                        Button("Folder", systemImage: "folder.badge.plus") { namePrompt = .newFolder(in: folderID, of: library) }
                        Button("Import PDF", systemImage: "arrow.down.doc") { isChoosingPDF = true }
                    }
                }
            }
        }
        .onChange(of: items.map(\.id)) { _, ids in
            selection.formIntersection(ids)
        }
        .namePrompt($namePrompt)
        .sheet(isPresented: $isCreatingNotebook, onDismiss: openCreatedNotebook) {
            NewNotebookSheet(folderID: folderID) { createdNotebook = $0 }
        }
        .sheet(item: $moveRequest) { request in
            MoveSheet(request: request) { endSelection() }
        }
        .fileImporter(isPresented: $isChoosingPDF, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await importPDFs(urls) }
            }
        }
        .alert(deletionTitle, isPresented: isConfirmingDeletion) {
            Button("Delete", role: .destructive) {
                let ids = itemsToDelete.map(\.id)
                library.perform { try library.delete(ids) }
                endSelection()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deletionMessage)
        }
    }

    @ViewBuilder private func cell(for item: LibraryEntry) -> some View {
        let button = Button {
            activate(item)
        } label: {
            LibraryEntryCell(
                item: item,
                isSelected: isSelecting ? selection.contains(item.id) : nil,
                isDropTarget: dropTarget.map { .folder($0) == item.id } ?? false
            )
        }
        .buttonStyle(.plain)
        .draggable(containerItemID: item.id)
        .contextMenu {
            Button("Rename", systemImage: "pencil") { namePrompt = .rename(item, in: library) }
            Button("Move", systemImage: "folder") { moveRequest = MoveRequest(items: [item]) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { itemsToDelete = [item] }
        }

        switch item {
        case .folder(let folder):
            button
                .springLoadingBehavior(.enabled)
                .libraryDropDestination(folder.id, isTargeted: Binding {
                    dropTarget == folder.id
                } set: { isTargeted in
                    if isTargeted {
                        dropTarget = folder.id
                    } else if dropTarget == folder.id {
                        dropTarget = nil
                    }
                })
        case .notebook:
            button
        }
    }

    /// A tap selects while selecting, except during a drag, where it opens a folder to drop into.
    private func activate(_ item: LibraryEntry) {
        if isSelecting && !isDragging {
            if selection.remove(item.id) == nil {
                selection.insert(item.id)
            }
        } else {
            navigator.open(item)
        }
    }

    private func selectedItems(in items: [LibraryEntry]) -> [LibraryEntry] {
        items.filter { selection.contains($0.id) }
    }

    private func endSelection() {
        isSelecting = false
        selection = []
    }

    private var title: String {
        if isSelecting {
            return selection.isEmpty ? String(localized: "Select Items") : String(localized: "\(selection.count) Selected")
        }
        return folderID.flatMap(library.library.folder)?.name ?? String(localized: "Library")
    }

    private var deletionTitle: String {
        if let item = itemsToDelete.first, itemsToDelete.count == 1 {
            String(localized: "Delete “\(item.name)”?")
        } else {
            String(localized: "Delete \(itemsToDelete.count) Items?")
        }
    }

    private var deletionMessage: String {
        let folderCount = itemsToDelete.count { if case .folder = $0 { true } else { false } }
        return switch (folderCount, itemsToDelete.count) {
        case (0, _): String(localized: "This can't be undone.")
        case (1, 1): String(localized: "The folder and everything in it will be deleted. This can't be undone.")
        default: String(localized: "Folders are deleted with everything in them. This can't be undone.")
        }
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding {
            !itemsToDelete.isEmpty
        } set: { isPresented in
            if !isPresented { itemsToDelete = [] }
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

private extension View {
    /// Moves library items dropped here into `destination`, the root when `nil`.
    func libraryDropDestination(_ destination: Folder.ID?, isTargeted: Binding<Bool>) -> some View {
        modifier(LibraryDropDestination(destination: destination, isTargeted: isTargeted))
    }
}

private struct LibraryDropDestination: ViewModifier {
    let destination: Folder.ID?
    @Binding var isTargeted: Bool

    @Environment(LibraryModel.self) private var library

    func body(content: Content) -> some View {
        content
            .dropDestination(for: LibraryDragItem.self) { items, _ in
                isTargeted = false
                library.perform { try library.move(items.map(\.id), to: destination) }
            }
            .dropConfiguration { session in
                DropConfiguration(operation: accepts(session) ? .move : .forbidden)
            }
            .onDropSessionUpdated { session in
                switch session.phase {
                case .entering, .active: isTargeted = accepts(session)
                default: isTargeted = false
                }
            }
    }

    private func accepts(_ session: DropSession) -> Bool {
        let items = session.localSession?.draggedItemIDs(for: LibraryEntry.ID.self) ?? []
        return library.library.canMove(items, to: destination)
    }
}

private struct LibraryEntryCell: View {
    let item: LibraryEntry
    /// `nil` outside of selecting.
    let isSelected: Bool?
    let isDropTarget: Bool

    @Environment(LibraryModel.self) private var library

    var body: some View {
        VStack(spacing: 10) {
            picture
                .frame(height: 190, alignment: .bottom)
                .overlay(alignment: .bottomTrailing) {
                    if let isSelected {
                        SelectionMark(isSelected: isSelected)
                            .offset(x: 6, y: 6)
                    }
                }
                .scaleEffect(isDropTarget ? 1.08 : 1)
                .background {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.tint.opacity(isDropTarget ? 0.18 : 0))
                        .padding(-10)
                }
                .animation(.snappy(duration: 0.2), value: isDropTarget)
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
        .accessibilityAddTraits(isSelected == true ? [.isButton, .isSelected] : .isButton)
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

private struct SelectionMark: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary), isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
            .background(.background, in: .circle)
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
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
