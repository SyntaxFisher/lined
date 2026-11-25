import Foundation
import ImageIO
import LinedModel
import LinedRendering
import LinedStorage
import PencilKit
import UniformTypeIdentifiers

/// Pictures of each notebook's first page for the library, cached in memory and on disk.
///
/// A cover is valid while it is at least as new as the notebook's last change, so covers never
/// need explicit invalidation and can be deleted with the caches directory at any time. The covers
/// of deleted notebooks stay behind until the next launch clears them out.
actor CoverStore {
    private let directory: URL
    private let packages: NotebookPackageStore
    private let memory = NSCache<NSUUID, CachedCover>()

    init(directory: URL, packages: NotebookPackageStore) {
        self.directory = directory
        self.packages = packages
    }

    func cover(for notebook: Notebook) async -> CGImage? {
        let key = notebook.id.rawValue as NSUUID
        if let cached = memory.object(forKey: key), cached.date >= notebook.modifiedAt {
            return cached.image
        }
        let image: CGImage?
        if let stored = storedCover(for: notebook) {
            image = stored
        } else {
            image = await renderCover(for: notebook)
            if let image {
                store(image, for: notebook)
            }
        }
        if let image {
            memory.setObject(CachedCover(image: image, date: .now), forKey: key)
        }
        return image
    }

    /// Deletes the stored covers of all notebooks but the given ones.
    func removeCovers(keeping notebooks: Set<Notebook.ID>) {
        let kept = Set(notebooks.map(fileURL(for:)).map(\.lastPathComponent))
        let stored = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in stored where !kept.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func renderCover(for notebook: Notebook) async -> CGImage? {
        let package = packages.package(for: notebook.id)
        guard let page = try? package.readDocument().pages.first else { return nil }
        let background = page.backgroundRenderer { try? PDFDocumentSource(url: package.pdfSourceURL($0)) }
        let drawing = (try? package.readDrawing(for: page.id)).flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
        return await PageThumbnailRenderer.image(
            pageSize: page.size.cgSize, background: background, drawing: drawing, maxPixelLength: 640
        )
    }

    private func storedCover(for notebook: Notebook) -> CGImage? {
        let url = fileURL(for: notebook.id)
        guard let written = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              written >= notebook.modifiedAt,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    private func store(_ image: CGImage, for notebook: Notebook) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let type = UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(fileURL(for: notebook.id) as CFURL, type, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    private func fileURL(for notebookID: Notebook.ID) -> URL {
        directory.appending(path: "\(notebookID).jpg", directoryHint: .notDirectory)
    }
}

private nonisolated final class CachedCover {
    let image: CGImage
    let date: Date

    init(image: CGImage, date: Date) {
        self.image = image
        self.date = date
    }
}
