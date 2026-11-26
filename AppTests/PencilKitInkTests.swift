import LinedInk
import LinedLayout
import LinedModel
import PencilKit
import Testing
@testable import Lined

/// PencilKit strokes as the page logic sees them.
struct PencilKitInkTests {
    private let layout = PageStackLayout(pageSizes: [CGSize](repeating: CGSize(width: 595, height: 842), count: 3))

    @Test func aStrokeIntoTheNextPageIsCutOffAtTheEdgeOfItsOwn() throws {
        let first = layout.frame(ofPageAt: 0)
        let second = layout.frame(ofPageAt: 1)
        let stroke = PKStroke.line(from: CGPoint(x: first.midX, y: first.maxY - 60), to: CGPoint(x: first.midX + 40, y: second.minY + 60))

        let clipped = try #require(DocumentInk.strokesClippedToTheirPages([stroke], layout: layout))

        let part = try #require(clipped.first)
        #expect(clipped.count == 1)
        #expect(part.id != stroke.id)
        #expect(DocumentInk.pageIndex(of: part, layout: layout) == 0)
        #expect(first.insetBy(dx: -0.5, dy: -0.5).contains(part.renderBounds))
        let below = CGRect(x: first.minX, y: first.maxY, width: first.width, height: second.maxY - first.maxY)
        #expect(PKDrawing(strokes: clipped).inkedPixels(in: below.insetBy(dx: 0, dy: 1)) == 0)
    }

    @Test func aClippedStrokeShowsAllTheInkOfTheStrokeOnItsPage() throws {
        let first = layout.frame(ofPageAt: 0)
        let second = layout.frame(ofPageAt: 1)
        let stroke = PKStroke.line(from: CGPoint(x: 100, y: first.maxY - 100), to: CGPoint(x: 300, y: second.minY + 100), width: 4)

        let clipped = try #require(DocumentInk.strokesClippedToTheirPages([stroke], layout: layout))

        let whole = PKDrawing(strokes: [stroke]).inkedPixels(in: first)
        let kept = PKDrawing(strokes: clipped).inkedPixels(in: first)
        #expect(abs(whole - kept) <= whole / 50)
    }

    /// The stroke eraser takes a stroke away wherever its mask is touched.
    @Test func aClippedStrokeIsErasedOnlyNearItsLine() throws {
        let first = layout.frame(ofPageAt: 0)
        let second = layout.frame(ofPageAt: 1)
        let stroke = PKStroke.line(from: CGPoint(x: 100, y: first.maxY - 100), to: CGPoint(x: 300, y: second.minY + 100), width: 4)

        let part = try #require(DocumentInk.strokesClippedToTheirPages([stroke], layout: layout)?.first)

        let mask = try #require(part.mask)
        let toPath = part.transform.inverted()
        let onLine = try #require(part.path.first { first.contains($0.location.applying(part.transform)) }).location
        #expect(mask.contains(onLine))
        for far in [CGPoint(x: first.midX, y: first.midY), CGPoint(x: first.maxX - 20, y: first.minY + 20), CGPoint(x: first.maxX - 20, y: first.maxY - 20)] {
            #expect(!mask.contains(far.applying(toPath)), "\(far)")
        }
    }

    /// A width outside PencilKit's range would be drawn like its neighbour.
    @Test func everyWidthIsOneThatPencilKitDraws() throws {
        var settings = ToolSettings()
        for style in ToolSettings.PenStyle.allCases {
            settings.penStyle = style
            for width in StrokeWidth.allCases {
                settings.penWidth = width
                let ink: PKInkingTool.InkType = style == .pen ? .pen : .monoline
                #expect(ink.validWidthRange.contains(CGFloat(settings.penLineWidth)), "\(style) \(width)")
            }
        }
        for width in StrokeWidth.allCases {
            settings.highlighterWidth = width
            #expect(PKInkingTool.InkType.marker.validWidthRange.contains(CGFloat(settings.highlighterLineWidth)), "\(width)")
        }
    }

    @Test func aStrokeThatStaysOnItsPageIsLeftAlone() {
        let first = layout.frame(ofPageAt: 0)
        let stroke = PKStroke.line(from: CGPoint(x: first.minX + 50, y: first.minY + 50), to: CGPoint(x: first.maxX - 50, y: first.maxY - 50))

        #expect(DocumentInk.strokesClippedToTheirPages([stroke], layout: layout) == nil)
    }

    @Test func aClippedStrokeStaysOnItsPageWhenItIsMovedToAnotherPlaceInTheStack() throws {
        let first = layout.frame(ofPageAt: 0)
        let second = layout.frame(ofPageAt: 1)
        let stroke = PKStroke.line(from: CGPoint(x: 200, y: second.minY + 60), to: CGPoint(x: 220, y: first.maxY - 60))
        let part = try #require(DocumentInk.strokesClippedToTheirPages([stroke], layout: layout)?.first)

        // Stored in page points and placed on the page again, as the notebook does.
        let lifted = DocumentInk.lifted([part], fromPageAt: 1, layout: layout)
        let placed = DocumentInk.strokes(joining: [2: lifted], layout: layout)

        #expect(DocumentInk.pageIndex(of: placed[0], layout: layout) == 2)
        #expect(DocumentInk.strokesClippedToTheirPages(placed, layout: layout) == nil)
    }
}
