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
        pages = (0..<pageCount).map { _ in Page(size: PageSize(format: .a4, orientation: .portrait), background: .paper(.squared)) }
        layout = PageStackLayout(pageSizes: pages.map(\.size.cgSize))
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
            let page = CGRect(origin: .zero, size: first.size).insetBy(dx: -0.5, dy: -0.5)
            #expect(change.after.allSatisfy { page.contains($0.renderBounds) })
            #expect(PKDrawing(strokes: change.after).inkedPixels(in: page) > 50)
        }
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
