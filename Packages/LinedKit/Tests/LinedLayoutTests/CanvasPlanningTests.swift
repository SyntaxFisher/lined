import CoreGraphics
import Testing
@testable import LinedLayout

struct BackgroundRenderPlannerTests {
    private let planner = BackgroundRenderPlanner(maxBasePixels: 1_000_000, detailMargin: 0.25)
    private let pageSize = CGSize(width: 500, height: 500)
    private let page = CGRect(x: 0, y: 0, width: 500, height: 500)

    @Test func rendersTheBaseAtScreenResolutionWithinTheBudget() {
        let request = planner.baseRequest(pageSize: pageSize, pixelsPerPoint: 1.5)

        #expect(request == RasterRequest(region: page, scale: 1.5))
        #expect(planner.detailRequest(pageSize: pageSize, visibleRect: page, pixelsPerPoint: 1.5, current: nil) == nil)
    }

    @Test func capsTheBaseAtThePixelBudget() {
        let request = planner.baseRequest(pageSize: pageSize, pixelsPerPoint: 8)

        #expect(request.scale == 2)
        #expect(request.region == page)
    }

    @Test func addsAPixelAlignedDetailImageBeyondTheBudget() throws {
        let visible = CGRect(x: 100.3, y: 200.2, width: 100, height: 120)
        let request = try #require(planner.detailRequest(pageSize: pageSize, visibleRect: visible, pixelsPerPoint: 8, current: nil))

        #expect(request.scale == 8)
        #expect(request.region.contains(visible))
        #expect(request.region == CGRect(x: 75.25, y: 170.125, width: 150.125, height: 180.125))
    }

    @Test func keepsDetailImagesInsideThePage() throws {
        let visible = CGRect(x: 450, y: -40, width: 100, height: 120)
        let request = try #require(planner.detailRequest(pageSize: pageSize, visibleRect: visible, pixelsPerPoint: 8, current: nil))

        #expect(request.region == CGRect(x: 425, y: 0, width: 75, height: 110))
    }

    @Test func reusesADetailImageWhileItCoversTheVisiblePart() throws {
        let visible = CGRect(x: 100, y: 200, width: 100, height: 120)
        let current = try #require(planner.detailRequest(pageSize: pageSize, visibleRect: visible, pixelsPerPoint: 8, current: nil))

        let nudged = visible.offsetBy(dx: 20, dy: -10)
        let moved = visible.offsetBy(dx: 60, dy: 0)

        #expect(planner.detailRequest(pageSize: pageSize, visibleRect: nudged, pixelsPerPoint: 8, current: current) == current)
        #expect(planner.detailRequest(pageSize: pageSize, visibleRect: moved, pixelsPerPoint: 8, current: current) != current)
        #expect(planner.detailRequest(pageSize: pageSize, visibleRect: visible, pixelsPerPoint: 6, current: current)?.scale == 6)
    }

    @Test func needsNoDetailForAPageOutsideTheViewport() {
        let below = CGRect(x: 0, y: 600, width: 100, height: 120)
        #expect(planner.detailRequest(pageSize: pageSize, visibleRect: below, pixelsPerPoint: 8, current: nil) == nil)
    }
}
