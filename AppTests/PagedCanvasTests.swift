import LinedInk
import LinedLayout
import LinedModel
import LinedRendering
import PencilKit
import Testing
import UIKit
@testable import Lined

/// A paged canvas in a window of the app, driven the way PencilKit drives it.
@MainActor
private final class CanvasHarness: PagedCanvasDelegate {
    let undoManager = NotebookUndoManager()
    let view = PagedCanvasView(frame: CGRect(x: 0, y: 0, width: 834, height: 1194))
    let pages: [Page]
    let layout: PageStackLayout
    private(set) var reports: [[PageInkChange]] = []
    private let window: UIWindow

    init(pageCount: Int = 3) async throws {
        pages = (0..<pageCount).map { _ in Page(size: PageSize.a4(.portrait), background: .paper(.squared)) }
        layout = PageStackLayout(pageSizes: pages.map(\.size.cgSize), scale: PagedCanvasView.documentScale)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = view.frame
        window.addSubview(view)
        window.isHidden = false
        view.delegate = self
        view.setPages(pages)
        view.layoutIfNeeded()
        try await settle()
    }

    var canvas: PKCanvasView {
        view.subviews.compactMap { $0 as? PKCanvasView }.first!
    }

    /// The view that holds the page backgrounds.
    var pagesView: UIView {
        canvas.subviews.first { $0.subviews.contains { $0 is PageBackgroundView } }!
    }

    var deskView: UIView {
        canvas.subviews.first { $0 is DeskView }!
    }

    /// Draws a stroke as the pencil does: the tool begins, the stroke appears, the tool lifts.
    func draw(_ stroke: PKStroke) async throws {
        view.canvasViewDidBeginUsingTool(canvas)
        var drawing = canvas.drawing
        drawing.strokes.append(stroke)
        canvas.drawing = drawing
        view.canvasViewDrawingDidChange(canvas)
        view.canvasViewDidEndUsingTool(canvas)
        try await settle()
    }

    /// Gives stored ink time to arrive and drawn ink time to settle.
    func settle() async throws {
        try await Task.sleep(for: .milliseconds(400))
    }

    func close() {
        window.isHidden = true
    }

    func backgroundRenderer(for page: Page) -> any PageBackgroundRenderer {
        page.backgroundRenderer { _ in nil }
    }

    func ink(for pageID: Page.ID) async -> [PKStroke] { [] }
    func canvasDidEndDisplayingInk(of pageID: Page.ID) {}
    func canvasDidChangeInk(_ changes: [PageInkChange]) { reports.append(changes) }
    func canvasDidShowPage(at index: Int) {}
}

@MainActor
struct PagedCanvasTests {
    @Test func aStrokeDrawnAcrossTwoPagesStaysOnBoth() async throws {
        let canvas = try await CanvasHarness()
        defer { canvas.close() }
        let first = canvas.layout.frame(ofPageAt: 0)
        let second = canvas.layout.frame(ofPageAt: 1)

        try await canvas.draw(.line(from: CGPoint(x: first.midX, y: first.maxY - 80), to: CGPoint(x: first.midX + 60, y: second.minY + 80)))

        let shown = canvas.canvas.drawing
        #expect(shown.strokes.count == 2)
        #expect(shown.inkedPixels(in: first) > 50)
        #expect(shown.inkedPixels(in: second) > 50)

        // One step to undo, with the ink of both pages, each in its own page's points.
        #expect(canvas.reports.count == 1)
        let step = try #require(canvas.reports.first)
        #expect(step.map(\.pageID) == [canvas.pages[0].id, canvas.pages[1].id])
        for change in step {
            #expect(change.before.isEmpty)
            #expect(change.after.count == 1)
            let page = CGRect(origin: .zero, size: canvas.pages[0].size.cgSize).insetBy(dx: -0.5, dy: -0.5)
            #expect(change.after.allSatisfy { page.contains($0.renderBounds) })
            #expect(PKDrawing(strokes: change.after).inkedPixels(in: page) > 10)
        }
    }

    @Test func pagesKeepTheirInkInPagePointsAndShowAtTheirFrame() async throws {
        let canvas = try await CanvasHarness()
        defer { canvas.close() }
        let first = canvas.layout.frame(ofPageAt: 0)
        let scale = PagedCanvasView.documentScale
        let drawn = PKStroke.line(from: CGPoint(x: first.minX + 100, y: first.minY + 100), to: CGPoint(x: first.minX + 300, y: first.minY + 100), width: 4)

        try await canvas.draw(drawn)

        let stored = try #require(canvas.reports.first?.first?.after.first)
        #expect(abs(stored.renderBounds.height - drawn.renderBounds.height / scale) < 0.5)
        #expect(abs(stored.renderBounds.minX - (drawn.renderBounds.minX - first.minX) / scale) < 0.5)
        let background = try #require(canvas.pagesView.subviews.compactMap { $0 as? PageBackgroundView }.first { $0.frame.minY < first.midY })
        #expect(background.bounds.size == canvas.pages[0].size.cgSize)
        #expect(abs(background.frame.width - first.width) < 0.01 && abs(background.frame.minY - first.minY) < 0.5)
    }

    @Test func aHeldLineBecomesItsShapeInOneStep() async throws {
        let canvas = try await CanvasHarness()
        defer { canvas.close() }
        let first = canvas.layout.frame(ofPageAt: 0)
        let center = CGPoint(x: first.midX, y: first.minY + 400)
        let wobblyCircle = (0...80).map { step in
            let angle = 2.02 * CGFloat.pi * CGFloat(step) / 80
            let radius = 150 + 6 * sin(angle * 5)
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }

        canvas.view.canvasViewDidBeginUsingTool(canvas.canvas)
        #expect(canvas.view.snapToShape(wobblyCircle))
        // The shape is in the pen's hand until the pen lifts, and no step before that.
        try await canvas.settle()
        #expect(canvas.reports.isEmpty)
        canvas.view.releaseShape()
        try await canvas.settle()

        let shown = canvas.canvas.drawing
        #expect(shown.strokes.count == 1)
        let ring = try #require(shown.strokes.first).renderBounds
        #expect(abs(ring.width - ring.height) < 1)
        #expect(abs(ring.midX - center.x) < 10 && abs(ring.midY - center.y) < 10)
        // The canvas draws the ring, and its middle stays empty.
        #expect(shown.inkedPixels(in: ring) > 500)
        #expect(shown.inkedPixels(in: ring.insetBy(dx: 60, dy: 60)) == 0)
        #expect(canvas.reports.count == 1)
        #expect(canvas.reports.first?.first?.after.count == 1)
    }

    @Test func aShapeFollowsThePenThatHoldsItAndIsOneStep() async throws {
        let canvas = try await CanvasHarness()
        defer { canvas.close() }
        let first = canvas.layout.frame(ofPageAt: 0)
        let start = CGPoint(x: first.minX + 100, y: first.minY + 300)
        let line = (0...50).map { CGPoint(x: start.x + CGFloat($0) * 6, y: start.y + 3 * sin(CGFloat($0) / 4)) }

        canvas.view.canvasViewDidBeginUsingTool(canvas.canvas)
        #expect(canvas.view.snapToShape(line))
        let end = try #require(line.last)
        canvas.view.pullShape(from: end, to: CGPoint(x: start.x + 150, y: start.y + 150))
        canvas.view.pullShape(from: end, to: CGPoint(x: start.x, y: start.y + 500))
        canvas.view.releaseShape()
        try await canvas.settle()

        let shown = canvas.canvas.drawing
        #expect(shown.strokes.count == 1)
        let bounds = try #require(shown.strokes.first).renderBounds
        #expect(bounds.width < 10)
        #expect(abs(bounds.minY - start.y) < 5 && abs(bounds.maxY - (start.y + 500)) < 5)
        #expect(shown.inkedPixels(in: bounds) > 300)
        #expect(canvas.reports.count == 1)
    }

    @Test func aTappedShapeIsChangedByItsHandlesInOneStep() async throws {
        let canvas = try await CanvasHarness()
        defer { canvas.close() }
        let first = canvas.layout.frame(ofPageAt: 0)
        let corners = [CGPoint(x: 200, y: 200), CGPoint(x: 500, y: 200), CGPoint(x: 350, y: 450)].map { CGPoint(x: first.minX + $0.x, y: first.minY + $0.y) }
        let triangle = PKStroke(.polyline(corners: corners, isClosed: true), ink: PKInk(.monoline, color: .black), pointSize: 3, pointSpacing: 4)
        try await canvas.draw(triangle)
        try await canvas.draw(.line(from: CGPoint(x: first.minX + 100, y: first.minY + 700), to: CGPoint(x: first.minX + 300, y: first.minY + 760)))

        // Neither a stroke drawn by hand nor the empty middle of the shape is taken hold of.
        #expect(!canvas.view.selectShape(at: CGPoint(x: first.minX + 200, y: first.minY + 730)))
        #expect(!canvas.view.selectShape(at: CGPoint(x: first.minX + 350, y: first.minY + 290)))
        #expect(canvas.view.selectShape(at: CGPoint(x: first.minX + 350, y: first.minY + 203)))

        canvas.view.moveShapeHandle(at: 2, to: CGPoint(x: first.minX + 350, y: first.minY + 600))
        try await canvas.settle()

        let shown = canvas.canvas.drawing
        #expect(shown.strokes.count == 2)
        #expect(abs(shown.strokes[0].renderBounds.maxY - (first.minY + 600)) < 5)
        #expect(shown.strokes[0].shape == .polyline(corners: [corners[0], corners[1], CGPoint(x: first.minX + 350, y: first.minY + 600)], isClosed: true))
        #expect(canvas.reports.count == 3)
        #expect(canvas.reports.last?.first?.before.count == 2)
        #expect(canvas.reports.last?.first?.after.count == 2)
    }

    @Test func aShapeIsStillOneAfterItsPageStoredIt() async throws {
        let canvas = try await CanvasHarness()
        defer { canvas.close() }
        let first = canvas.layout.frame(ofPageAt: 0)
        let circle = RecognizedShape.ellipse(center: CGPoint(x: first.midX, y: first.minY + 300), semiAxes: CGSize(width: 80, height: 80), rotation: 0)
        try await canvas.draw(PKStroke(circle, ink: PKInk(.monoline, color: .black), pointSize: 3, pointSpacing: 4))

        let stored = try #require(canvas.reports.first?.first?.after.first)
        let reloaded = try #require(try PKDrawing(data: PKDrawing(strokes: [stored]).dataRepresentation()).strokes.first)
        guard case .ellipse(_, let semiAxes, _) = reloaded.shape else {
            Issue.record("not an ellipse")
            return
        }
        // The page keeps its ink in page points.
        #expect(abs(semiAxes.width - 80 / PagedCanvasView.documentScale) < 0.01)
    }

    @Test func aHeldLineThatIsNoShapeStaysWithThePen() async throws {
        let canvas = try await CanvasHarness()
        defer { canvas.close() }
        let first = canvas.layout.frame(ofPageAt: 0)
        let wave = (0...200).map { CGPoint(x: first.minX + 100 + CGFloat($0) * 3, y: first.minY + 300 + 80 * sin(CGFloat($0) / 8)) }
        let dash = [CGPoint(x: first.minX + 100, y: first.minY + 100), CGPoint(x: first.minX + 110, y: first.minY + 100)]

        canvas.view.canvasViewDidBeginUsingTool(canvas.canvas)
        #expect(!canvas.view.snapToShape(wave))
        #expect(!canvas.view.snapToShape(dash))
        canvas.view.canvasViewDidEndUsingTool(canvas.canvas)
        try await canvas.settle()

        #expect(canvas.canvas.drawing.strokes.isEmpty)
        #expect(canvas.reports.isEmpty)
    }

    @Test func strokesOnOnePageAreOneStepEach() async throws {
        let canvas = try await CanvasHarness()
        defer { canvas.close() }
        let first = canvas.layout.frame(ofPageAt: 0)

        try await canvas.draw(.line(from: CGPoint(x: first.minX + 100, y: first.minY + 100), to: CGPoint(x: first.minX + 300, y: first.minY + 150)))
        try await canvas.draw(.line(from: CGPoint(x: first.minX + 100, y: first.minY + 200), to: CGPoint(x: first.minX + 300, y: first.minY + 250)))

        #expect(canvas.reports.count == 2)
        #expect(canvas.reports.map { $0.map(\.after.count) } == [[1], [2]])
        #expect(canvas.canvas.drawing.strokes.count == 2)
    }

    /// A zoom beyond its limit springs back once the fingers lift: the canvas takes its final zoom
    /// at once and animates the view it magnifies there. The pages and the desk must take the same
    /// way, or for a moment they show elsewhere than the ink.
    ///
    /// UIKit animates a zoom that went beyond the largest one by itself, and one that went below the
    /// smallest inside an animation block, where the canvas reports the zoom too.
    @Test(arguments: [false, true])
    func pagesAndDeskSpringBackWithTheInk(insideAnimationBlock: Bool) async throws {
        let canvas = try await CanvasHarness()
        defer { canvas.close() }
        let scroll = canvas.canvas
        let target = insideAnimationBlock ? scroll.minimumZoomScale : scroll.maximumZoomScale
        let start = insideAnimationBlock ? scroll.maximumZoomScale : target * 1.5
        let magnified = try #require(scroll.subviews.first {
            $0 !== canvas.pagesView && $0 !== canvas.deskView && abs($0.transform.a - scroll.zoomScale) < 0.0001
        })

        if insideAnimationBlock {
            scroll.zoomScale = start
            UIView.animate(withDuration: 1) { scroll.zoomScale = target }
        } else {
            let springBack = CABasicAnimation(keyPath: "transform")
            springBack.fromValue = CATransform3DMakeScale(start, start, 1)
            springBack.toValue = CATransform3DMakeScale(target, target, 1)
            springBack.duration = 1
            magnified.layer.add(springBack, forKey: "transform")
            scroll.zoomScale = target
        }
        try await Task.sleep(for: .milliseconds(100))

        let ink = try #require(magnified.layer.presentation()?.transform.m11)
        let pages = try #require(canvas.pagesView.layer.presentation()?.transform.m11)
        let desk = try #require(canvas.deskView.layer.presentation()?.transform.m11)
        // The ink is still on its way back.
        #expect(abs(ink - target) > target * 0.05)
        #expect(abs(pages - ink) < 0.001)
        #expect(abs(desk - ink) < 0.001)
    }
}
