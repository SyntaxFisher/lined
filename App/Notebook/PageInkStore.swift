import LinedModel
import PencilKit

/// The ink of an open notebook's pages: loaded on demand, held in memory while a canvas shows a page
/// or the page has unsaved changes, and written back shortly after it changes.
final class PageInkStore {
    var onSave: (() -> Void)?
    var onSaveFailure: ((any Error) -> Void)?

    private let files: NotebookFiles
    private var strokes: [Page.ID: [PKStroke]] = [:]
    private var displayedPages: Set<Page.ID> = []
    private var unsavedPages: Set<Page.ID> = []
    private var scheduledSave: Task<Void, Never>?

    init(files: NotebookFiles) {
        self.files = files
    }

    /// The page's ink for showing it on screen. It stays in memory until `endDisplaying(_:)`.
    func beginDisplaying(_ pageID: Page.ID) async -> [PKStroke] {
        displayedPages.insert(pageID)
        if let held = strokes[pageID] { return held }
        let stored = await files.loadDrawing(for: pageID).strokes
        // An edit may have arrived while the file was being read.
        if let held = strokes[pageID] { return held }
        if displayedPages.contains(pageID) {
            strokes[pageID] = stored
        }
        return stored
    }

    func endDisplaying(_ pageID: Page.ID) {
        displayedPages.remove(pageID)
        releaseIfUnneeded(pageID)
    }

    /// The page's ink as one drawing, for a picture of the page.
    func drawing(for pageID: Page.ID) async -> PKDrawing {
        if let held = strokes[pageID] { return PKDrawing(strokes: held) }
        let stored = await files.loadDrawing(for: pageID)
        // An edit may have arrived while the file was being read.
        return strokes[pageID].map { PKDrawing(strokes: $0) } ?? stored
    }

    /// Takes the page's changed ink. While writing goes on, the ink reaches the disk about once
    /// a second, not after every stroke and not only when the writing pauses.
    ///
    /// The strokes are kept as they come: putting them together as a drawing takes time with every
    /// stroke of the page, and is left to the moment the page is saved.
    func setStrokes(_ strokes: [PKStroke], for pageID: Page.ID) {
        self.strokes[pageID] = strokes
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
        strokes[pageID] = nil
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
            guard let strokes = strokes[pageID] else { continue }
            do {
                try await files.saveDrawing(PKDrawing(strokes: strokes), for: pageID)
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
            strokes[pageID] = nil
        }
    }
}
