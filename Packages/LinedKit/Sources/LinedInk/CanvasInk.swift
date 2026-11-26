import LinedLayout

/// A change to the ink of one page, in page points.
public struct InkChange<PageID: Hashable, Stroke: InkStroke> {
    public let pageID: PageID
    public let before: [Stroke]
    public let after: [Stroke]

    public init(pageID: PageID, before: [Stroke], after: [Stroke]) {
        self.pageID = pageID
        self.before = before
        self.after = after
    }

    /// The change that undoes this one.
    public var reversed: InkChange {
        InkChange(pageID: pageID, before: after, after: before)
    }
}

extension InkChange: Sendable where PageID: Sendable, Stroke: Sendable {}

/// The record of the ink a canvas holds: which pages have their ink in it, and what that ink was
/// when it was last compared.
///
/// A canvas holds the ink of the pages near its viewport only. Comparing its strokes with this record
/// tells which pages changed, which is what gets saved and what an undo step restores.
public struct CanvasInk<PageID: Hashable, Stroke: InkStroke> {
    private struct Entry {
        var strokes: [Stroke]
        var fingerprint: InkFingerprint
    }

    private var entries: [PageID: Entry] = [:]

    public init() {}

    /// The pages whose ink is in the canvas.
    public var pageIDs: Set<PageID> { Set(entries.keys) }

    public func contains(_ pageID: PageID) -> Bool {
        entries[pageID] != nil
    }

    /// Notes the ink of a page as the canvas holds it now, in page points.
    public mutating func set(_ strokes: [Stroke], for pageID: PageID) {
        entries[pageID] = Entry(strokes: strokes, fingerprint: InkFingerprint(of: strokes))
    }

    public mutating func remove(_ pageID: PageID) {
        entries[pageID] = nil
    }

    public struct Comparison {
        /// The pages whose ink differs from the record, in the order of the layout. The record has
        /// been brought up to date with them.
        public var changes: [InkChange<PageID, Stroke>] = []
        /// Pages that have strokes in the canvas although their ink is not in it. Their strokes are
        /// left out of `changes`: without the page's stored ink, they are not all of its ink.
        public var pagesMissingInk: Set<PageID> = []
    }

    /// Compares the strokes of a canvas with the record.
    ///
    /// - Parameter pageIDs: The pages in the order of the layout.
    public mutating func compare(with strokes: [Stroke], layout: PageStackLayout, pageIDs: [PageID]) -> Comparison {
        let indexByPageID = Dictionary(uniqueKeysWithValues: zip(pageIDs, pageIDs.indices))
        var changes: [(index: Int, change: InkChange<PageID, Stroke>)] = []
        let current = DocumentInk.strokesByPage(in: strokes, layout: layout)
        var comparison = Comparison()
        for index in current.keys where index < pageIDs.count && entries[pageIDs[index]] == nil {
            comparison.pagesMissingInk.insert(pageIDs[index])
        }
        // Fingerprints are taken where the strokes lie; only a changed page has its strokes converted.
        for (pageID, entry) in entries {
            guard let index = indexByPageID[pageID] else { continue }
            let onPage = current[index] ?? []
            let fingerprint = InkFingerprint(of: onPage, relativeTo: layout.frame(ofPageAt: index).origin)
            guard fingerprint != entry.fingerprint else { continue }
            let ink = DocumentInk.lifted(onPage, fromPageAt: index, layout: layout)
            changes.append((index, InkChange(pageID: pageID, before: entry.strokes, after: ink)))
            entries[pageID] = Entry(strokes: ink, fingerprint: fingerprint)
        }
        comparison.changes = changes.sorted { $0.index < $1.index }.map(\.change)
        return comparison
    }
}
