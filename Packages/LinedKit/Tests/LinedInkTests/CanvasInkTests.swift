import CoreGraphics
import LinedLayout
import Testing
@testable import LinedInk

struct CanvasInkTests {
    private let layout = PageStackLayout(pageSizes: [CGSize](repeating: CGSize(width: 600, height: 800), count: 4))
    private let pageIDs = ["a", "b", "c", "d"]
    private let stored = [TestStroke(10, 20)]

    private func onPage(_ index: Int, _ x: CGFloat, _ y: CGFloat) -> TestStroke {
        let origin = layout.frame(ofPageAt: index).origin
        return TestStroke(origin.x + x, origin.y + y)
    }

    @Test func reportsNothingWhileTheCanvasShowsWhatWasLoaded() {
        var record = CanvasInk<String, TestStroke>()
        record.set(stored, for: "b")
        record.set([], for: "c")

        let comparison = record.compare(with: DocumentInk.strokes(joining: [1: stored], layout: layout), layout: layout, pageIDs: pageIDs)

        #expect(comparison.changes.isEmpty)
        #expect(comparison.pagesMissingInk.isEmpty)
    }

    @Test func reportsAChangedPageOnceWithItsInkBeforeAndAfter() {
        var record = CanvasInk<String, TestStroke>()
        record.set(stored, for: "b")
        record.set([], for: "c")
        let canvas = DocumentInk.strokes(joining: [1: stored], layout: layout) + [onPage(1, 100, 100)]

        let first = record.compare(with: canvas, layout: layout, pageIDs: pageIDs)
        let second = record.compare(with: canvas, layout: layout, pageIDs: pageIDs)

        #expect(first.changes.map(\.pageID) == ["b"])
        #expect(first.changes[0].before == stored)
        #expect(first.changes[0].after == stored + [TestStroke(100, 100)])
        #expect(second.changes.isEmpty)
    }

    @Test func reportsAPageThatLostAllItsInk() {
        var record = CanvasInk<String, TestStroke>()
        record.set(stored, for: "b")

        let comparison = record.compare(with: [], layout: layout, pageIDs: pageIDs)

        #expect(comparison.changes.map(\.pageID) == ["b"])
        #expect(comparison.changes[0].after.isEmpty)
    }

    @Test func reportsEveryPageAnEditTouches() {
        var record = CanvasInk<String, TestStroke>()
        record.set(stored, for: "b")
        record.set([], for: "c")
        // The stroke of the second page is moved onto the third.
        let moved = DocumentInk.strokes(joining: [2: stored], layout: layout)

        let comparison = record.compare(with: moved, layout: layout, pageIDs: pageIDs)

        #expect(Set(comparison.changes.map(\.pageID)) == ["b", "c"])
    }

    @Test func holdsBackStrokesOnAPageWhoseInkIsNotInTheCanvas() {
        var record = CanvasInk<String, TestStroke>()
        record.set([], for: "a")
        let canvas = [onPage(3, 50, 50)]

        let early = record.compare(with: canvas, layout: layout, pageIDs: pageIDs)

        #expect(early.changes.isEmpty)
        #expect(early.pagesMissingInk == ["d"])

        // The page's stored ink arrives and is put beneath the stroke.
        record.set(stored, for: "d")
        let merged = DocumentInk.strokes(canvas, adding: stored, beneathPageAt: 3, layout: layout)
        let late = record.compare(with: merged, layout: layout, pageIDs: pageIDs)

        #expect(late.changes.map(\.pageID) == ["d"])
        #expect(late.changes[0].before == stored)
        #expect(late.changes[0].after == stored + [TestStroke(50, 50)])
        #expect(late.pagesMissingInk.isEmpty)
    }

    @Test func forgetsAPageThatLeftTheCanvas() {
        var record = CanvasInk<String, TestStroke>()
        record.set(stored, for: "b")
        record.remove("b")

        let comparison = record.compare(with: [], layout: layout, pageIDs: pageIDs)

        #expect(comparison.changes.isEmpty)
        #expect(record.pageIDs.isEmpty)
    }

    @Test func aReversedChangeSwapsBeforeAndAfter() {
        let change = InkChange(pageID: "a", before: [TestStroke](), after: stored)

        #expect(change.reversed.before == stored)
        #expect(change.reversed.after.isEmpty)
    }

    @Test func notesAddedStrokesLikeAComparisonWould() {
        var added = CanvasInk<String, TestStroke>()
        added.set(stored, for: "b")
        added.set([], for: "c")
        var compared = added
        let loaded = DocumentInk.strokes(joining: [1: stored], layout: layout)
        let new = [onPage(2, 5, 5), onPage(1, 100, 100), onPage(1, 200, 200)]

        let fromAdding = added.add(new, layout: layout, pageIDs: pageIDs)
        let fromComparing = compared.compare(with: loaded + new, layout: layout, pageIDs: pageIDs)

        #expect(fromAdding.changes.map(\.pageID) == ["b", "c"])
        #expect(fromAdding.changes.map(\.before) == fromComparing.changes.map(\.before))
        #expect(fromAdding.changes.map(\.after) == fromComparing.changes.map(\.after))
        #expect(fromAdding.changes[0].after == stored + [TestStroke(100, 100), TestStroke(200, 200)])
        // After adding, the record agrees with the canvas as a comparison sees it.
        #expect(added.compare(with: loaded + new, layout: layout, pageIDs: pageIDs).changes.isEmpty)
    }

    @Test func leavesAddedStrokesOfAPageWithoutItsInkForLater() {
        var record = CanvasInk<String, TestStroke>()
        record.set(stored, for: "b")

        let comparison = record.add([onPage(2, 5, 5)], layout: layout, pageIDs: pageIDs)

        #expect(comparison.changes.isEmpty)
        #expect(comparison.pagesMissingInk == ["c"])
    }
}
