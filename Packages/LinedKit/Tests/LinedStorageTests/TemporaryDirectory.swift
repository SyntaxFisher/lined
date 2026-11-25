import Foundation

/// A scratch directory that is removed when the test that owns it ends.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "LinedStorageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func file(_ name: String) -> URL {
        url.appending(path: name, directoryHint: .notDirectory)
    }

    func contents(of directory: URL? = nil) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: (directory ?? url).path(percentEncoded: false))) ?? []).sorted()
    }
}
