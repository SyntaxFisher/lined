import Foundation

/// The on-disk layout of a library: one index file and one package directory per notebook.
public struct StorageLocation: Equatable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var libraryIndex: URL { root.appending(path: "library.json", directoryHint: .notDirectory) }

    public var notebooks: URL { root.appending(path: "Notebooks", directoryHint: .isDirectory) }

    /// The library inside the app's Application Support directory.
    public static func applicationSupport() throws -> StorageLocation {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return StorageLocation(root: support.appending(path: "Library", directoryHint: .isDirectory))
    }
}

public enum StorageError: Error, Equatable, Sendable {
    /// The file was written by a newer version of the app.
    case unsupportedFormatVersion(found: Int, supported: Int)
    case corruptFile(URL)
    case notebookAlreadyExists
}
