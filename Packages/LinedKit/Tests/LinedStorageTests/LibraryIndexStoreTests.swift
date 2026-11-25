import Foundation
import LinedModel
import Testing
@testable import LinedStorage

struct LibraryIndexStoreTests {
    private let directory: TemporaryDirectory
    private let store: LibraryIndexStore

    init() throws {
        directory = try TemporaryDirectory()
        store = LibraryIndexStore(fileURL: directory.url.appending(path: "nested/library.json"))
    }

    @Test func loadsAnEmptyLibraryBeforeTheFirstSave() throws {
        #expect(try store.load() == Library())
    }

    @Test func roundTripsFoldersAndNotebooks() throws {
        var library = Library()
        let created = Date(timeIntervalSince1970: 1_764_000_000.125)
        let folder = try library.createFolder(named: "Physics", in: nil, at: created)
        let notebook = try library.addNotebook(titled: "Waves / Optics", in: folder.id, at: created.addingTimeInterval(60.5))

        try store.save(library)
        let loaded = try store.load()

        #expect(loaded == library)
        #expect(loaded.notebook(notebook.id)?.createdAt == created.addingTimeInterval(60.5))
    }

    @Test func writesReadableVersionedJSON() throws {
        var library = Library()
        try library.createFolder(named: "Physics", in: nil, at: Date(timeIntervalSince1970: 0))
        try store.save(library)

        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.contains(#""formatVersion" : 1"#))
        #expect(text.contains(#""createdAt" : "1970-01-01T00:00:00.000Z""#))
    }

    @Test func refusesAnIndexWrittenByANewerVersion() throws {
        try store.save(Library())
        try Data(#"{"formatVersion": 99, "folders": [], "notebooks": [], "tags": []}"#.utf8).write(to: store.fileURL)

        #expect(throws: StorageError.unsupportedFormatVersion(found: 99, supported: 1)) { try store.load() }
    }

    @Test func reportsAndQuarantinesACorruptIndex() throws {
        try store.save(Library())
        try Data("not json".utf8).write(to: store.fileURL)

        #expect(throws: StorageError.corruptFile(store.fileURL)) { try store.load() }

        let quarantined = try store.quarantine(at: Date(timeIntervalSince1970: 42))
        #expect(quarantined.lastPathComponent == "library.corrupt-42.json")
        #expect(try store.load() == Library())
    }
}
