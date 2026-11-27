import Foundation

public enum LibraryError: Error, Equatable, Sendable {
    case emptyName
    case folderNotFound
    case notebookNotFound
    case folderCannotContainItself
}

/// The catalog of folders and notebooks. Folders form a tree; a `nil` parent is the library root.
public struct Library: Equatable, Sendable {
    private var foldersByID: [Folder.ID: Folder]
    private var notebooksByID: [Notebook.ID: Notebook]

    public init(folders: [Folder] = [], notebooks: [Notebook] = []) {
        foldersByID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        notebooksByID = Dictionary(notebooks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        repairHierarchy()
    }

    // MARK: Queries

    public var folders: [Folder] {
        foldersByID.values.sorted { ($0.createdAt, $0.id.description) < ($1.createdAt, $1.id.description) }
    }

    public var notebooks: [Notebook] {
        notebooksByID.values.sorted { ($0.createdAt, $0.id.description) < ($1.createdAt, $1.id.description) }
    }

    public func folder(_ id: Folder.ID) -> Folder? { foldersByID[id] }

    public func notebook(_ id: Notebook.ID) -> Notebook? { notebooksByID[id] }

    public func entry(_ id: LibraryEntry.ID) -> LibraryEntry? {
        switch id {
        case .folder(let id): foldersByID[id].map(LibraryEntry.folder)
        case .notebook(let id): notebooksByID[id].map(LibraryEntry.notebook)
        }
    }

    public func contents(of folderID: Folder.ID?, sortedBy order: LibrarySortOrder) -> [LibraryEntry] {
        let folders = foldersByID.values.filter { $0.parentID == folderID }.map(LibraryEntry.folder)
        let notebooks = notebooksByID.values.filter { $0.folderID == folderID }.map(LibraryEntry.notebook)
        return (folders + notebooks).sorted(by: order.areInIncreasingOrder)
    }

    public func itemCount(in folderID: Folder.ID?) -> Int {
        foldersByID.values.count { $0.parentID == folderID } + notebooksByID.values.count { $0.folderID == folderID }
    }

    /// The folders from the root down to and including `folderID`.
    public func path(to folderID: Folder.ID) -> [Folder] {
        var path: [Folder] = []
        var current = foldersByID[folderID]
        while let folder = current {
            path.append(folder)
            current = folder.parentID.flatMap { foldersByID[$0] }
        }
        return path.reversed()
    }

    public struct FolderNode: Identifiable, Hashable, Sendable {
        public let folder: Folder
        public let depth: Int
        public var id: Folder.ID { folder.id }
    }

    /// Every folder in depth-first order, siblings sorted by name.
    public func folderHierarchy() -> [FolderNode] {
        let childrenByParent = Dictionary(grouping: foldersByID.values, by: \.parentID)
        var nodes: [FolderNode] = []
        func append(childrenOf parentID: Folder.ID?, depth: Int) {
            let children = (childrenByParent[parentID] ?? []).sorted {
                LibrarySortOrder.name.areInIncreasingOrder(.folder($0), .folder($1))
            }
            for child in children {
                nodes.append(FolderNode(folder: child, depth: depth))
                append(childrenOf: child.id, depth: depth + 1)
            }
        }
        append(childrenOf: nil, depth: 0)
        return nodes
    }

    public func canMove(_ item: LibraryEntry.ID, to destination: Folder.ID?) -> Bool {
        if let destination, foldersByID[destination] == nil { return false }
        switch item {
        case .notebook(let id):
            return notebooksByID[id] != nil
        case .folder(let id):
            guard foldersByID[id] != nil else { return false }
            guard let destination else { return true }
            return !path(to: destination).contains { $0.id == id }
        }
    }

    /// Whether all items may move to the destination and at least one of them is somewhere else.
    public func canMove(_ items: [LibraryEntry.ID], to destination: Folder.ID?) -> Bool {
        items.allSatisfy { canMove($0, to: destination) } && items.contains { entry($0)?.parentID != destination }
    }

    // MARK: Mutations

    @discardableResult
    public mutating func createFolder(
        named name: String,
        in parentID: Folder.ID?,
        id: Folder.ID = Folder.ID(),
        at date: Date = .now
    ) throws(LibraryError) -> Folder {
        let name = try Self.validatedName(name)
        try requireFolder(parentID)
        let folder = Folder(id: id, name: name, parentID: parentID, createdAt: date, modifiedAt: date)
        foldersByID[id] = folder
        touchFolder(parentID, at: date)
        return folder
    }

    @discardableResult
    public mutating func addNotebook(
        id: Notebook.ID = Notebook.ID(),
        titled title: String,
        in folderID: Folder.ID?,
        at date: Date = .now
    ) throws(LibraryError) -> Notebook {
        let title = try Self.validatedName(title)
        try requireFolder(folderID)
        let notebook = Notebook(id: id, title: title, folderID: folderID, createdAt: date, modifiedAt: date)
        notebooksByID[id] = notebook
        touchFolder(folderID, at: date)
        return notebook
    }

    public mutating func rename(_ item: LibraryEntry.ID, to name: String, at date: Date = .now) throws(LibraryError) {
        let name = try Self.validatedName(name)
        switch item {
        case .folder(let id):
            guard foldersByID[id] != nil else { throw .folderNotFound }
            foldersByID[id]?.name = name
            foldersByID[id]?.modifiedAt = date
        case .notebook(let id):
            guard notebooksByID[id] != nil else { throw .notebookNotFound }
            notebooksByID[id]?.title = name
        }
    }

    public mutating func move(_ item: LibraryEntry.ID, to destination: Folder.ID?, at date: Date = .now) throws(LibraryError) {
        try requireFolder(destination)
        let origin: Folder.ID?
        switch item {
        case .folder(let id):
            guard let folder = foldersByID[id] else { throw .folderNotFound }
            guard canMove(item, to: destination) else { throw .folderCannotContainItself }
            origin = folder.parentID
            foldersByID[id]?.parentID = destination
        case .notebook(let id):
            guard let notebook = notebooksByID[id] else { throw .notebookNotFound }
            origin = notebook.folderID
            notebooksByID[id]?.folderID = destination
        }
        guard origin != destination else { return }
        touchFolder(origin, at: date)
        touchFolder(destination, at: date)
    }

    /// Moves every item, or none of them when one cannot move.
    public mutating func move(_ items: [LibraryEntry.ID], to destination: Folder.ID?, at date: Date = .now) throws(LibraryError) {
        var draft = self
        for item in items {
            try draft.move(item, to: destination, at: date)
        }
        self = draft
    }

    /// Removes the item, and for a folder everything inside it. Returns the notebooks that left the library.
    @discardableResult
    public mutating func delete(_ item: LibraryEntry.ID, at date: Date = .now) throws(LibraryError) -> Set<Notebook.ID> {
        switch item {
        case .notebook(let id):
            guard let notebook = notebooksByID.removeValue(forKey: id) else { throw .notebookNotFound }
            touchFolder(notebook.folderID, at: date)
            return [id]
        case .folder(let id):
            guard let folder = foldersByID[id] else { throw .folderNotFound }
            let removedFolders = Set(foldersByID.values.filter { path(to: $0.id).contains { $0.id == id } }.map(\.id))
            let removedNotebooks = Set(notebooksByID.values.filter { $0.folderID.map(removedFolders.contains) ?? false }.map(\.id))
            removedFolders.forEach { foldersByID.removeValue(forKey: $0) }
            removedNotebooks.forEach { notebooksByID.removeValue(forKey: $0) }
            touchFolder(folder.parentID, at: date)
            return removedNotebooks
        }
    }

    /// Removes every item. An item inside a folder that is removed as well goes with that folder.
    @discardableResult
    public mutating func delete(_ items: [LibraryEntry.ID], at date: Date = .now) throws(LibraryError) -> Set<Notebook.ID> {
        var draft = self
        var removedNotebooks: Set<Notebook.ID> = []
        for item in items where entry(item) == nil || draft.entry(item) != nil {
            removedNotebooks.formUnion(try draft.delete(item, at: date))
        }
        self = draft
        return removedNotebooks
    }

    public mutating func markNotebookModified(_ id: Notebook.ID, at date: Date = .now) {
        notebooksByID[id]?.modifiedAt = date
    }

    /// Aligns the catalog with the notebook packages that exist on disk: entries without a package are dropped,
    /// packages without an entry are adopted into the root. Returns whether anything changed.
    @discardableResult
    public mutating func reconcile(storedNotebooks: Set<Notebook.ID>, recoveredTitle: String, at date: Date = .now) -> Bool {
        let known = Set(notebooksByID.keys)
        let missing = known.subtracting(storedNotebooks)
        let orphaned = storedNotebooks.subtracting(known)
        missing.forEach { notebooksByID.removeValue(forKey: $0) }
        for id in orphaned {
            notebooksByID[id] = Notebook(id: id, title: recoveredTitle, folderID: nil, createdAt: date, modifiedAt: date)
        }
        return !missing.isEmpty || !orphaned.isEmpty
    }

    // MARK: Invariants

    private static func validatedName(_ name: String) throws(LibraryError) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyName }
        return trimmed
    }

    private func requireFolder(_ id: Folder.ID?) throws(LibraryError) {
        if let id, foldersByID[id] == nil { throw .folderNotFound }
    }

    private mutating func touchFolder(_ id: Folder.ID?, at date: Date) {
        guard let id else { return }
        foldersByID[id]?.modifiedAt = date
    }

    /// Items whose parent is missing or part of a cycle move to the root, so every item stays reachable.
    private mutating func repairHierarchy() {
        for folder in folders where !reachesRoot(folder) {
            foldersByID[folder.id]?.parentID = nil
        }
        for notebook in notebooksByID.values {
            if let folderID = notebook.folderID, foldersByID[folderID] == nil {
                notebooksByID[notebook.id]?.folderID = nil
            }
        }
    }

    private func reachesRoot(_ folder: Folder) -> Bool {
        var visited: Set<Folder.ID> = [folder.id]
        var parentID = foldersByID[folder.id]?.parentID
        while let id = parentID {
            guard let parent = foldersByID[id], visited.insert(id).inserted else { return false }
            parentID = parent.parentID
        }
        return true
    }
}
