import CoreGraphics
import Testing
@testable import LinedInk

struct StrokeEraserTests {
    /// A horizontal line from x = 0 to x = 100 with a point every unit.
    private let line = (0...100).map { StrokeEraser.LinePoint(location: CGPoint(x: CGFloat($0), y: 0), reach: 1) }

    @Test func cutsWhatLiesUnderTheEraserAndAMarginOnEitherSide() {
        let runs = StrokeEraser.remainingRuns(
            of: line, sweptFrom: CGPoint(x: 50, y: -30), to: CGPoint(x: 50, y: 30), radius: 4, margin: 4
        )

        // Under the eraser: 45 to 55. With the margin: 41 to 59.
        #expect(runs == [0..<41, 60..<101])
    }

    @Test func leavesALineItDoesNotTouchAlone() {
        let runs = StrokeEraser.remainingRuns(
            of: line, sweptFrom: CGPoint(x: 30, y: 6.1), to: CGPoint(x: 60, y: 6.1), radius: 5, margin: 5
        )

        #expect(runs == nil)
    }

    @Test func takesAPieceWhenTheEraserOnlyGrazesTheInk() {
        let runs = StrokeEraser.remainingRuns(
            of: line, sweptFrom: CGPoint(x: 30, y: 6), to: CGPoint(x: 30, y: 6), radius: 5, margin: 5
        )

        #expect(runs == [0..<25, 36..<101])
    }

    @Test func dropsWhatWouldBeASinglePoint() {
        let runs = StrokeEraser.remainingRuns(
            of: line, sweptFrom: CGPoint(x: 0, y: 0), to: CGPoint(x: 90, y: 0), radius: 0.5, margin: 9
        )

        #expect(runs == [])
    }

    @Test func measuresTheMarginAlongTheLine() {
        // Out to x = 10 and back again just below, so that both legs lie close together.
        let hairpin = (0...10).map { CGPoint(x: CGFloat($0), y: 0) } + (0...10).map { CGPoint(x: CGFloat(10 - $0), y: 1) }
        let points = hairpin.map { StrokeEraser.LinePoint(location: $0, reach: 0) }

        let runs = StrokeEraser.remainingRuns(
            of: points, sweptFrom: CGPoint(x: 2, y: -3), to: CGPoint(x: 2, y: -3), radius: 3, margin: 1
        )

        // Only the point at x = 2 lies under the eraser. The second leg stays, the point at x = 0 is
        // left on its own and goes.
        #expect(runs == [4..<22])
    }

    @Test func findsTheLineBetweenPointsFarApart() {
        let sparse = [0, 50, 100].map { StrokeEraser.LinePoint(location: CGPoint(x: CGFloat($0), y: 0), reach: 1) }

        let runs = StrokeEraser.remainingRuns(
            of: sparse, sweptFrom: CGPoint(x: 25, y: -20), to: CGPoint(x: 25, y: 20), radius: 2, margin: 0
        )

        #expect(runs == [])
        let missed = StrokeEraser.remainingRuns(
            of: sparse, sweptFrom: CGPoint(x: 25, y: 4), to: CGPoint(x: 75, y: 4), radius: 2, margin: 0
        )
        #expect(missed == nil)
    }

    @Test func keepsWhatTheLineDoesNotShow() {
        let hidden = line.map { point in
            StrokeEraser.LinePoint(location: point.location, reach: 0, isErasable: point.location.x > 50)
        }

        let runs = StrokeEraser.remainingRuns(
            of: hidden, sweptFrom: CGPoint(x: 40, y: 0), to: CGPoint(x: 60, y: 0), radius: 0, margin: 3
        )

        #expect(runs == [0..<51, 64..<101])
    }
}
