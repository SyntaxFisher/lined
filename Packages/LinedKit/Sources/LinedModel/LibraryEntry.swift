import Foundation

public struct Folder: Identifiable, Hashable, Codable, Sendable {
    public typealias ID = Identifier<Folder>

    public let id: ID
    public var name: String
    public var parentID: ID?
    public let createdAt: Date
    public var modifiedAt: Date

    public init(id: ID = ID(), name: String, parentID: ID?, createdAt: Date, modifiedAt: Date) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// The library's record of a notebook. Its pages live in the notebook's own package.
public struct Notebook: Identifiable, Hashable, Codable, Sendable {
    public typealias ID = Identifier<Notebook>

    public let id: ID
    public var title: String
    public var folderID: Folder.ID?
    public let createdAt: Date
    public var modifiedAt: Date

    public init(id: ID = ID(), title: String, folderID: Folder.ID?, createdAt: Date, modifiedAt: Date) {
        self.id = id
        self.title = title
        self.folderID = folderID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public enum LibraryEntry: Identifiable, Hashable, Sendable {
    case folder(Folder)
    case notebook(Notebook)

    public enum ID: Hashable, Codable, Sendable {
        case folder(Folder.ID)
        case notebook(Notebook.ID)
    }

    public var id: ID {
        switch self {
        case .folder(let folder): .folder(folder.id)
        case .notebook(let notebook): .notebook(notebook.id)
        }
    }

    public var name: String {
        switch self {
        case .folder(let folder): folder.name
        case .notebook(let notebook): notebook.title
        }
    }

    public var parentID: Folder.ID? {
        switch self {
        case .folder(let folder): folder.parentID
        case .notebook(let notebook): notebook.folderID
        }
    }

    public var createdAt: Date {
        switch self {
        case .folder(let folder): folder.createdAt
        case .notebook(let notebook): notebook.createdAt
        }
    }

    public var modifiedAt: Date {
        switch self {
        case .folder(let folder): folder.modifiedAt
        case .notebook(let notebook): notebook.modifiedAt
        }
    }

    var isFolder: Bool {
        if case .folder = self { true } else { false }
    }
}

public enum LibrarySortOrder: String, CaseIterable, Codable, Sendable {
    case name
    case dateModified
    case dateCreated

    /// Folders always precede notebooks; names ascend, dates descend.
    func areInIncreasingOrder(_ lhs: LibraryEntry, _ rhs: LibraryEntry) -> Bool {
        if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
        switch self {
        case .name:
            break
        case .dateModified:
            if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        case .dateCreated:
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        }
        let comparison = lhs.name.localizedStandardCompare(rhs.name)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.createdAt < rhs.createdAt
    }
}
