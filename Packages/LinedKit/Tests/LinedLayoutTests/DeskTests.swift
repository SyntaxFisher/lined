import CoreGraphics
import Testing
@testable import LinedLayout

struct DeskTests {
    private let area = CGRect(x: 0, y: 0, width: 100, height: 200)

    @Test func isTheWholeAreaWithoutPages() {
        #expect(Desk.rects(around: [], in: area) == [area])
    }

    @Test func surroundsAPage() {
        let page = CGRect(x: 10, y: 20, width: 80, height: 100)

        #expect(Desk.rects(around: [page], in: area) == [
            CGRect(x: 0, y: 0, width: 100, height: 20),
            CGRect(x: 0, y: 20, width: 10, height: 100),
            CGRect(x: 90, y: 20, width: 10, height: 100),
            CGRect(x: 0, y: 120, width: 100, height: 80),
        ])
    }

    @Test func fillsTheGapBetweenTwoPages() {
        let upper = CGRect(x: 10, y: 0, width: 80, height: 90)
        let lower = CGRect(x: 20, y: 100, width: 60, height: 100)

        #expect(Desk.rects(around: [upper, lower], in: area) == [
            CGRect(x: 0, y: 0, width: 10, height: 90),
            CGRect(x: 90, y: 0, width: 10, height: 90),
            CGRect(x: 0, y: 90, width: 100, height: 10),
            CGRect(x: 0, y: 100, width: 20, height: 100),
            CGRect(x: 80, y: 100, width: 20, height: 100),
        ])
    }

    @Test func leavesNothingBesideAPageThatFillsTheArea() {
        let page = CGRect(x: -50, y: -50, width: 300, height: 400)
        #expect(Desk.rects(around: [page], in: area).isEmpty)
    }

    @Test func ignoresPagesOutsideTheArea() {
        let above = CGRect(x: 10, y: -300, width: 80, height: 100)
        let inside = CGRect(x: 10, y: 150, width: 80, height: 100)

        #expect(Desk.rects(around: [above, inside], in: area) == [
            CGRect(x: 0, y: 0, width: 100, height: 150),
            CGRect(x: 0, y: 150, width: 10, height: 50),
            CGRect(x: 90, y: 150, width: 10, height: 50),
        ])
    }

    @Test func coversExactlyWhatThePagesLeave() {
        let pages = [CGRect(x: 10, y: 5, width: 70, height: 60), CGRect(x: 30, y: 75, width: 65, height: 110)]
        let covered = Desk.rects(around: pages, in: area).reduce(0) { $0 + $1.width * $1.height }
        let paper = pages.reduce(0) { $0 + $1.width * $1.height }

        #expect(covered + paper == area.width * area.height)
    }
}
