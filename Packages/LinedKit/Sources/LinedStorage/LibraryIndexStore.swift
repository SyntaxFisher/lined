import Foundation
import LinedModel

/// Reads and writes the library catalog as a single JSON file.
public struct LibraryIndexStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Returns an empty library when no index has been written yet.
    public func load() throws -> Library {
        guard FileManager.default.itemExists(at: fileURL) else { return Library() }
        let file = try VersionedJSON.read(LibraryFile.self, from: fileURL)
        return Library(folders: file.folders, notebooks: file.notebooks)
    }

    public func save(_ library: Library) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try VersionedJSON.write(LibraryFile(library), to: fileURL)
    }

    /// Moves an unreadable index aside so a fresh one can be written without destroying the evidence.
    @discardableResult
    public func quarantine(at date: Date = .now) throws -> URL {
        let stamp = Int(date.timeIntervalSince1970)
        let destination = fileURL.deletingLastPathComponent()
            .appending(path: "library.corrupt-\(stamp).json", directoryHint: .notDirectory)
        try FileManager.default.moveItem(at: fileURL, to: destination)
        return destination
    }
}

private struct LibraryFile: VersionedFile {
    static let currentFormatVersion = 1

    var formatVersion = LibraryFile.currentFormatVersion
    var folders: [Folder]
    var notebooks: [Notebook]

    init(_ library: Library) {
        folders = library.folders
        notebooks = library.notebooks
    }
}
