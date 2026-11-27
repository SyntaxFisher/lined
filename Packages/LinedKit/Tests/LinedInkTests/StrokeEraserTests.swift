import CoreGraphics
import Testing
@testable import LinedInk

struct StrokeEraserTests {
    /// A horizontal line from x = 0 to x = 100 with a point every unit.
    private let line = (0...100).map { StrokeEraser.LinePoint(location: CGPoint(x: CGFloat($0), y: 0), reach: 1) }

    @Test func leavesALineItDoesNotTouchAlone() {
        let runs = StrokeEraser.remainingRuns(of: line, sweptFrom: CGPoint(x: 50, y: 20), to: CGPoint(x: 60, y: 20), radius: 5)

        #expect(runs == nil)
    }

    @Test func cutsTheSweptPartOutOfTheLine() throws {
        let runs = try #require(
            StrokeEraser.remainingRuns(of: line, sweptFrom: CGPoint(x: 50, y: -30), to: CGPoint(x: 50, y: 30), radius: 4)
        )

        #expect(runs == [0..<45, 56..<101])
    }

    @Test func takesTheWidthOfTheLineIntoAccount() throws {
        let wide = line.map { StrokeEraser.LinePoint(location: $0.location, reach: 6) }

        let runs = try #require(
            StrokeEraser.remainingRuns(of: wide, sweptFrom: CGPoint(x: 50, y: 9), to: CGPoint(x: 50, y: 9), radius: 4)
        )

        #expect(runs == [0..<46, 55..<101])
    }

    @Test func erasesTheEndAndDropsWhatWouldBeASinglePoint() throws {
        let runs = try #require(
            StrokeEraser.remainingRuns(of: line, sweptFrom: CGPoint(x: 0, y: 0), to: CGPoint(x: 98, y: 0), radius: 0.5)
        )

        #expect(runs == [])
    }

    @Test func keepsWhatTheLineDoesNotShow() throws {
        let hidden = line.map { point in
            StrokeEraser.LinePoint(location: point.location, reach: 1, isErasable: point.location.x > 50)
        }

        #expect(StrokeEraser.remainingRuns(of: hidden, sweptFrom: CGPoint(x: 20, y: 0), to: CGPoint(x: 30, y: 0), radius: 3) == nil)
        let runs = try #require(
            StrokeEraser.remainingRuns(of: hidden, sweptFrom: CGPoint(x: 40, y: 0), to: CGPoint(x: 60, y: 0), radius: 0)
        )
        #expect(runs == [0..<51, 62..<101])
    }
}
