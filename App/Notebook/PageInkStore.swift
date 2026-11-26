import LinedModel
import PencilKit

/// The ink of an open notebook's pages: loaded on demand, held in memory while a canvas shows a page
/// or the page has unsaved changes, and written back shortly after it changes.
final class PageInkStore {
    var onSave: (() -> Void)?
    var onSaveFailure: ((any Error) -> Void)?

    private let files: NotebookFiles
    private var drawings: [Page.ID: PKDrawing] = [:]
    private var displayedPages: Set<Page.ID> = []
    private var unsavedPages: Set<Page.ID> = []
    private var scheduledSave: Task<Void, Never>?

    init(files: NotebookFiles) {
        self.files = files
    }

    /// The page's ink for showing it on screen. It stays in memory until `endDisplaying(_:)`.
    func beginDisplaying(_ pageID: Page.ID) async -> PKDrawing {
        displayedPages.insert(pageID)
        return await drawing(for: pageID)
    }

    func endDisplaying(_ pageID: Page.ID) {
        displayedPages.remove(pageID)
        releaseIfUnneeded(pageID)
    }

    func drawing(for pageID: Page.ID) async -> PKDrawing {
        if let drawing = drawings[pageID] { return drawing }
        let stored = await files.loadDrawing(for: pageID)
        // An edit may have arrived while the file was being read.
        if let drawing = drawings[pageID] { return drawing }
        if displayedPages.contains(pageID) {
            drawings[pageID] = stored
        }
        return stored
    }

    /// Takes the page's changed ink. While writing goes on, the ink reaches the disk about once
    /// a second, not after every stroke and not only when the writing pauses.
    func setDrawing(_ drawing: PKDrawing, for pageID: Page.ID) {
        drawings[pageID] = drawing
        unsavedPages.insert(pageID)
        guard scheduledSave == nil else { return }
        scheduledSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    /// Forgets a page that has been removed from the notebook.
    func discard(_ pageID: Page.ID) {
        drawings[pageID] = nil
        displayedPages.remove(pageID)
        unsavedPages.remove(pageID)
    }

    /// Writes all unsaved ink. Ink that fails to save stays in memory and goes out with the next save.
    func save() async {
        scheduledSave = nil
        let pending = unsavedPages
        guard !pending.isEmpty else { return }
        unsavedPages.removeAll()
        for pageID in pending {
            guard let drawing = drawings[pageID] else { continue }
            do {
                try await files.saveDrawing(drawing, for: pageID)
            } catch {
                unsavedPages.insert(pageID)
                onSaveFailure?(error)
            }
        }
        pending.forEach(releaseIfUnneeded)
        onSave?()
    }

    private func releaseIfUnneeded(_ pageID: Page.ID) {
        if !displayedPages.contains(pageID), !unsavedPages.contains(pageID) {
            drawings[pageID] = nil
        }
    }
}
