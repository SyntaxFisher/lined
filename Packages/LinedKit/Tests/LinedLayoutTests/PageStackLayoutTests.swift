import CoreGraphics
import Testing
@testable import LinedLayout

struct PageStackLayoutTests {
    private let metrics = PageStackLayout.Metrics(margin: 10, spacing: 20)

    private var layout: PageStackLayout {
        PageStackLayout(
            pageSizes: [CGSize(width: 400, height: 600), CGSize(width: 600, height: 400), CGSize(width: 400, height: 600)],
            metrics: metrics
        )
    }

    @Test func stacksPagesCentredOnTheWidestOne() {
        #expect(layout.pageCount == 3)
        #expect(layout.contentSize == CGSize(width: 620, height: 1660))
        #expect(layout.frame(ofPageAt: 0) == CGRect(x: 110, y: 10, width: 400, height: 600))
        #expect(layout.frame(ofPageAt: 1) == CGRect(x: 10, y: 630, width: 600, height: 400))
        #expect(layout.frame(ofPageAt: 2) == CGRect(x: 110, y: 1050, width: 400, height: 600))
    }

    @Test func findsThePagesInAVerticalSpan() {
        func indices(from minY: CGFloat, to maxY: CGFloat) -> Range<Int> {
            layout.pageIndices(intersecting: CGRect(x: 0, y: minY, width: 620, height: maxY - minY))
        }

        #expect(indices(from: 0, to: 5) == 0..<0)
        #expect(indices(from: 0, to: 100) == 0..<1)
        #expect(indices(from: 600, to: 640) == 0..<2)
        #expect(indices(from: 610, to: 630) == 1..<1)
        #expect(indices(from: 700, to: 1100) == 1..<3)
        #expect(indices(from: -500, to: 5000) == 0..<3)
        #expect(indices(from: 1650, to: 1700) == 3..<3)
    }

    @Test func findsThePageNearestToAHeight() {
        #expect(layout.pageIndex(nearestTo: -50) == 0)
        #expect(layout.pageIndex(nearestTo: 300) == 0)
        #expect(layout.pageIndex(nearestTo: 615) == 0)
        #expect(layout.pageIndex(nearestTo: 625) == 1)
        #expect(layout.pageIndex(nearestTo: 1200) == 2)
        #expect(layout.pageIndex(nearestTo: 9000) == 2)
    }

    @Test func fitsTheStackToTheViewportWidth() {
        #expect(layout.zoom(fittingWidth: 1240) == 2)
    }

    @Test func magnifiesPagesAndSpacesByTheScale() {
        let scaled = PageStackLayout(
            pageSizes: [CGSize(width: 400, height: 600), CGSize(width: 600, height: 400)],
            metrics: metrics,
            scale: 2
        )

        #expect(scaled.contentSize == CGSize(width: 1240, height: 2080))
        #expect(scaled.frame(ofPageAt: 1) == CGRect(x: 20, y: 1260, width: 1200, height: 800))
        #expect(CGPoint(x: 10, y: 5).applying(scaled.transform(ofPageAt: 1)) == CGPoint(x: 40, y: 1270))
        #expect(scaled.zoom(fittingWidth: 1240) == 1)
    }

    @Test func anEmptyStackHasNoPages() {
        let empty = PageStackLayout(pageSizes: [], metrics: metrics)

        #expect(empty.contentSize == CGSize(width: 20, height: 0))
        #expect(empty.pageIndex(nearestTo: 0) == nil)
        #expect(empty.pageIndices(intersecting: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
    }
}

struct PixelGridTests {
    @Test func snapsToTheNearestPixel() {
        #expect(PixelGrid.snap(10.3, pixelsPerPoint: 2) == 10.5)
        #expect(PixelGrid.snap(CGPoint(x: 0.2, y: 0.8), pixelsPerPoint: 2) == CGPoint(x: 0, y: 1))
    }

    @Test func growsRectanglesToWholePixels() {
        let snapped = PixelGrid.snapOutward(CGRect(x: 10.3, y: 4.1, width: 20.3, height: 5), pixelsPerPoint: 2)
        #expect(snapped == CGRect(x: 10, y: 4, width: 21, height: 5.5))
    }

    @Test func keepsRectanglesThatAreAlreadyOnTheGrid() {
        let pixelsPerPoint: CGFloat = 3.4689
        let aligned = CGRect(x: 7 / pixelsPerPoint, y: 0, width: 2064 / pixelsPerPoint, height: 100 / pixelsPerPoint)
        let snapped = PixelGrid.snapOutward(aligned, pixelsPerPoint: pixelsPerPoint)

        #expect((snapped.width * pixelsPerPoint).rounded() == 2064)
        #expect(abs(snapped.minX - aligned.minX) < 1e-9)
    }
}
