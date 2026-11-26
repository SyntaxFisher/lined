import CoreGraphics
import LinedLayout
import Testing
@testable import LinedInk

struct DocumentInkTests {
    private let layout = PageStackLayout(
        pageSizes: [CGSize(width: 600, height: 800), CGSize(width: 400, height: 500), CGSize(width: 600, height: 800)],
        metrics: .init(margin: 10, spacing: 20)
    )

    @Test func placesPageInkAtThePagesPosition() {
        let document = DocumentInk.strokes(joining: [1: [TestStroke(5, 7)]], layout: layout)

        let frame = layout.frame(ofPageAt: 1)
        #expect(document == [TestStroke(frame.minX + 5, frame.minY + 7)])
    }

    @Test func returnsEveryPageItsOwnInkInPagePoints() {
        let pages = [0: [TestStroke(10, 20)], 2: [TestStroke(1, 2), TestStroke(500, 700)]]

        let split = DocumentInk.pageInk(in: DocumentInk.strokes(joining: pages, layout: layout), layout: layout)

        #expect(split == pages)
    }

    @Test func aStrokeBelongsToThePageItStartsOn() {
        let first = layout.frame(ofPageAt: 0)
        let startingAtTheEndOfTheFirstPage = TestStroke(first.minX + 100, first.maxY - 5)

        let split = DocumentInk.pageInk(in: [startingAtTheEndOfTheFirstPage], layout: layout)

        #expect(split == [0: [TestStroke(100, first.height - 5)]])
    }

    @Test func aStrokeStartingBetweenPagesGoesToTheNearestPage() {
        let second = layout.frame(ofPageAt: 1)

        let split = DocumentInk.pageInk(in: [TestStroke(200, second.minY - 3), TestStroke(200, -50)], layout: layout)

        #expect(split.mapValues(\.count) == [0: 1, 1: 1])
    }

    @Test func addsStoredInkBeneathWhatIsAlreadyThere() {
        let frame = layout.frame(ofPageAt: 1)
        let drawnMeanwhile = TestStroke(frame.minX + 9, frame.minY + 9)

        let document = DocumentInk.strokes([drawnMeanwhile], adding: [TestStroke(1, 1)], beneathPageAt: 1, layout: layout)

        #expect(DocumentInk.pageInk(in: document, layout: layout) == [1: [TestStroke(1, 1), TestStroke(9, 9)]])
    }

    @Test func removesAndReplacesTheInkOfSinglePages() {
        let pages = [0: [TestStroke(10, 20)], 1: [TestStroke(11, 21)], 2: [TestStroke(12, 22)]]
        let document = DocumentInk.strokes(joining: pages, layout: layout)

        let removed = DocumentInk.strokes(document, removingPagesAt: [0, 2], layout: layout)
        let replaced = DocumentInk.strokes(document, replacingPageAt: 1, with: [TestStroke(99, 98)], layout: layout)

        #expect(DocumentInk.pageInk(in: removed, layout: layout) == [1: [TestStroke(11, 21)]])
        #expect(DocumentInk.pageInk(in: replaced, layout: layout) == [0: [TestStroke(10, 20)], 1: [TestStroke(99, 98)], 2: [TestStroke(12, 22)]])
    }

    @Test func inkFollowsItsPageWhenTheStackChanges() {
        let before = PageStackLayout(pageSizes: [CGSize](repeating: CGSize(width: 600, height: 800), count: 3))
        // The first page is removed and a wide page is inserted before the last one.
        let after = PageStackLayout(pageSizes: [CGSize(width: 600, height: 800), CGSize(width: 900, height: 300), CGSize(width: 600, height: 800)])
        let pages = [0: [TestStroke(10, 20)], 1: [TestStroke(11, 21)], 2: [TestStroke(12, 22)]]

        let moved = DocumentInk.strokes(
            DocumentInk.strokes(joining: pages, layout: before),
            movedFrom: before,
            to: after,
            newIndices: [1: 0, 2: 2]
        )

        #expect(DocumentInk.pageInk(in: moved, layout: after) == [0: [TestStroke(11, 21)], 2: [TestStroke(12, 22)]])
    }
}

struct InkFingerprintTests {
    private let layout = PageStackLayout(pageSizes: [CGSize](repeating: CGSize(width: 595, height: 842), count: 40))
    private let ink = [TestStroke(12.3, 45.6), TestStroke(0.1, 0.2)]

    @Test func isTheSameInPageAndInDocumentCoordinates() {
        for index in [0, 1, 17, 39] {
            let document = DocumentInk.strokes(joining: [index: ink], layout: layout)
            let origin = layout.frame(ofPageAt: index).origin

            #expect(InkFingerprint(of: document, relativeTo: origin) == InkFingerprint(of: ink))
            #expect(InkFingerprint(of: DocumentInk.lifted(document, fromPageAt: index, layout: layout)) == InkFingerprint(of: ink))
        }
    }

    @Test func changesWhenAStrokeIsAddedRemovedMovedOrRecoloured() {
        let original = InkFingerprint(of: ink)

        #expect(InkFingerprint(of: ink + [TestStroke(5, 5)]) != original)
        #expect(InkFingerprint(of: Array(ink.dropLast())) != original)
        #expect(InkFingerprint(of: [ink[0].moved(by: CGVector(dx: 0.5, dy: 0)), ink[1]]) != original)
        #expect(InkFingerprint(of: [TestStroke(12.3, 45.6, colour: "red"), ink[1]]) != original)
    }

    @Test func dependsOnTheOrderOfTheStrokes() {
        #expect(InkFingerprint(of: Array(ink.reversed())) != InkFingerprint(of: ink))
    }
}
