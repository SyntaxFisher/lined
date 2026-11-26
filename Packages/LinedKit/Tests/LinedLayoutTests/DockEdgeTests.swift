import CoreGraphics
import Testing
@testable import LinedLayout

struct DockEdgeTests {
    private let size = CGSize(width: 1000, height: 1300)

    @Test func docksAtTheEdgeClosestToTheDropPoint() {
        #expect(DockEdge.nearest(to: CGPoint(x: 500, y: 1250), in: size) == .bottom)
        #expect(DockEdge.nearest(to: CGPoint(x: 500, y: 40), in: size) == .top)
        #expect(DockEdge.nearest(to: CGPoint(x: 30, y: 650), in: size) == .leading)
        #expect(DockEdge.nearest(to: CGPoint(x: 960, y: 650), in: size) == .trailing)
    }

    @Test func aDropBeyondTheContainerDocksAtTheEdgeItCrossed() {
        #expect(DockEdge.nearest(to: CGPoint(x: 1100, y: 200), in: size) == .trailing)
        #expect(DockEdge.nearest(to: CGPoint(x: 400, y: -30), in: size) == .top)
    }

    @Test func aDropInACornerPrefersTheBottomAndTheTop() {
        #expect(DockEdge.nearest(to: CGPoint(x: 0, y: 1300), in: size) == .bottom)
        #expect(DockEdge.nearest(to: CGPoint(x: 1000, y: 0), in: size) == .top)
    }

    @Test func onlyTheTopAndTheBottomLayTheBarOutInARow() {
        #expect(DockEdge.allCases.filter(\.isHorizontal) == [.top, .bottom])
    }
}
