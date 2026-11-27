import LinedInk
import LinedLayout
import LinedModel
import PencilKit
import Testing
@testable import Lined

/// PencilKit strokes as the page logic sees them.
struct PencilKitInkTests {
    private let layout = PageStackLayout(pageSizes: [CGSize](repeating: CGSize(width: 595, height: 842), count: 3))

    @Test func aStrokeAcrossTwoPagesIsSplitIntoOneStrokeOnEach() throws {
        let first = layout.frame(ofPageAt: 0)
        let second = layout.frame(ofPageAt: 1)
        let stroke = PKStroke.line(from: CGPoint(x: first.midX, y: first.maxY - 60), to: CGPoint(x: first.midX + 40, y: second.minY + 60))

        let parts = try #require(DocumentInk.strokesSplitAtPages([stroke], layout: layout))

        #expect(parts.count == 2)
        #expect(parts.map { DocumentInk.pageIndex(of: $0, layout: layout) } == [0, 1])
        #expect(Set(parts.map(\.id)).count == 2 && !parts.contains { $0.id == stroke.id })
        for (index, part) in parts.enumerated() {
            let page = layout.frame(ofPageAt: index)
            #expect(page.insetBy(dx: -0.5, dy: -0.5).contains(part.renderBounds))
            #expect(PKDrawing(strokes: [part]).inkedPixels(in: page) > 50)
        }
        // Nothing is drawn in the gap.
        let gap = CGRect(x: first.minX, y: first.maxY, width: first.width, height: second.minY - first.maxY)
        #expect(PKDrawing(strokes: parts).inkedPixels(in: gap.insetBy(dx: 0, dy: 1)) == 0)
    }

    @Test func theInkOfASplitStrokeIsTheInkOfTheStroke() throws {
        let first = layout.frame(ofPageAt: 0)
        let second = layout.frame(ofPageAt: 1)
        let stroke = PKStroke.line(from: CGPoint(x: 100, y: first.maxY - 100), to: CGPoint(x: 300, y: second.minY + 100), width: 4)

        let parts = try #require(DocumentInk.strokesSplitAtPages([stroke], layout: layout))

        for index in 0...1 {
            let page = layout.frame(ofPageAt: index)
            let whole = PKDrawing(strokes: [stroke]).inkedPixels(in: page)
            let split = PKDrawing(strokes: parts).inkedPixels(in: page)
            #expect(abs(whole - split) <= whole / 50)
        }
    }

    /// The stroke eraser takes a stroke away wherever its mask is touched.
    @Test func thePartsOfASplitStrokeAreErasedOnlyNearTheirLine() throws {
        let first = layout.frame(ofPageAt: 0)
        let second = layout.frame(ofPageAt: 1)
        let stroke = PKStroke.line(from: CGPoint(x: 100, y: first.maxY - 100), to: CGPoint(x: 300, y: second.minY + 100), width: 4)

        let parts = try #require(DocumentInk.strokesSplitAtPages([stroke], layout: layout))

        for (index, part) in parts.enumerated() {
            let page = layout.frame(ofPageAt: index)
            let mask = try #require(part.mask)
            let toPath = part.transform.inverted()
            let onLine = try #require(part.path.first { page.contains($0.location.applying(part.transform)) }).location
            #expect(mask.contains(onLine))
            for far in [CGPoint(x: page.midX, y: page.midY), CGPoint(x: page.maxX - 20, y: page.minY + 20), CGPoint(x: page.maxX - 20, y: page.maxY - 20)] {
                #expect(!mask.contains(far.applying(toPath)), "page \(index), \(far)")
            }
        }
    }

    /// A width outside PencilKit's range would be drawn like its neighbour.
    @Test func everyWidthIsOneThatPencilKitDraws() throws {
        var settings = ToolSettings()
        for width in StrokeWidth.allCases {
            settings.penWidth = width
            let drawnWidth = CGFloat(settings.penLineWidth) * PagedCanvasView.documentScale
            #expect(PKInkingTool.InkType.monoline.validWidthRange.contains(drawnWidth), "\(width)")
        }
    }

    @Test func aStrokeThatStaysOnItsPageIsLeftAlone() {
        let first = layout.frame(ofPageAt: 0)
        let stroke = PKStroke.line(from: CGPoint(x: first.minX + 50, y: first.minY + 50), to: CGPoint(x: first.maxX - 50, y: first.maxY - 50))

        #expect(DocumentInk.strokesSplitAtPages([stroke], layout: layout) == nil)
    }

    @Test func aSplitStrokeStaysOnItsPageWhenItIsMovedToAnotherPlaceInTheStack() throws {
        let first = layout.frame(ofPageAt: 0)
        let second = layout.frame(ofPageAt: 1)
        let stroke = PKStroke.line(from: CGPoint(x: 200, y: first.maxY - 60), to: CGPoint(x: 220, y: second.minY + 60))
        let parts = try #require(DocumentInk.strokesSplitAtPages([stroke], layout: layout))

        // Stored in page points and placed on the page again, as the notebook does.
        let lifted = DocumentInk.lifted([parts[1]], fromPageAt: 1, layout: layout)
        let placed = DocumentInk.strokes(joining: [2: lifted], layout: layout)

        #expect(DocumentInk.pageIndex(of: placed[0], layout: layout) == 2)
        #expect(DocumentInk.strokesSplitAtPages(placed, layout: layout) == nil)
    }
}
