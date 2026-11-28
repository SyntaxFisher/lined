import CoreGraphics
import Foundation
import Testing
@testable import LinedInk

/// Lines as a hand draws them: along a shape, but wavering, with round corners left as they are.
private enum Hand {
    /// Points along straight sides through `corners`, wavering by `waver` to either side.
    static func line(through corners: [CGPoint], waver: CGFloat = 2, spacing: CGFloat = 3) -> [CGPoint] {
        var points: [CGPoint] = []
        for (start, end) in zip(corners, corners.dropFirst()) {
            let steps = max(1, Int(start.distance(to: end) / spacing))
            points += (0..<steps).map { start.interpolated(to: end, by: CGFloat($0) / CGFloat(steps)) }
        }
        points.append(corners[corners.count - 1])
        return wavering(points, by: waver)
    }

    static func closedLine(through corners: [CGPoint], waver: CGFloat = 2) -> [CGPoint] {
        // The hand starts a little way into the first side and stops short of where it began.
        let start = corners[0].interpolated(to: corners[1], by: 0.3)
        let end = corners[0].interpolated(to: corners[1], by: 0.25)
        return line(through: [start] + corners.dropFirst() + [corners[0], end], waver: waver)
    }

    static func ellipse(center: CGPoint, semiAxes: CGSize, rotation: CGFloat = 0, sweep: CGFloat = 1.97 * .pi, waver: CGFloat = 2) -> [CGPoint] {
        let turn = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: rotation)
        let points = (0...120).map { step in
            let angle = 0.4 + sweep * CGFloat(step) / 120
            return CGPoint(x: semiAxes.width * cos(angle), y: semiAxes.height * sin(angle)).applying(turn)
        }
        return wavering(points, by: waver)
    }

    private static func wavering(_ points: [CGPoint], by waver: CGFloat) -> [CGPoint] {
        points.enumerated().map { index, point in
            let phase = CGFloat(index)
            return CGPoint(
                x: point.x + waver * (0.6 * sin(phase * 0.21) + 0.4 * sin(phase * 0.57 + 1)),
                y: point.y + waver * (0.6 * cos(phase * 0.17 + 2) + 0.4 * sin(phase * 0.43))
            )
        }
    }
}

private func corners(of shape: RecognizedShape?, closed: Bool) -> [CGPoint]? {
    guard case .polyline(let corners, let isClosed) = shape, isClosed == closed else { return nil }
    return corners
}

private func isNear(_ point: CGPoint, _ other: CGPoint, within distance: CGFloat = 8) -> Bool {
    point.distance(to: other) <= distance
}

/// Whether each of `expected` has one of `corners` near it, and there are no more corners than that.
private func match(_ corners: [CGPoint], _ expected: [CGPoint], within distance: CGFloat = 8) -> Bool {
    corners.count == expected.count && expected.allSatisfy { point in corners.contains { isNear($0, point, within: distance) } }
}

struct ShapeRecognizerTests {
    @Test func aWaveringLineBecomesStraightBetweenItsEnds() throws {
        let shape = ShapeRecognizer.shape(for: Hand.line(through: [CGPoint(x: 20, y: 30), CGPoint(x: 320, y: 180)]))
        let corners = try #require(corners(of: shape, closed: false))
        #expect(match(corners, [CGPoint(x: 20, y: 30), CGPoint(x: 320, y: 180)]))
    }

    @Test func aNearlyHorizontalLineBecomesHorizontal() throws {
        let shape = ShapeRecognizer.shape(for: Hand.line(through: [CGPoint(x: 20, y: 100), CGPoint(x: 420, y: 112)]))
        let corners = try #require(corners(of: shape, closed: false))
        #expect(corners.count == 2)
        #expect(corners[0].y == corners[1].y)
    }

    @Test func aNearlyVerticalLineBecomesVertical() throws {
        let shape = ShapeRecognizer.shape(for: Hand.line(through: [CGPoint(x: 100, y: 20), CGPoint(x: 90, y: 400)]))
        let corners = try #require(corners(of: shape, closed: false))
        #expect(corners[0].x == corners[1].x)
    }

    @Test func aSlightBowIsStillALine() throws {
        let bow = (0...60).map { CGPoint(x: CGFloat($0) * 5, y: 100 + 9 * sin(CGFloat($0) / 60 * .pi)) }
        #expect(corners(of: ShapeRecognizer.shape(for: bow), closed: false)?.count == 2)
    }

    @Test func anAngleKeepsItsCorner() throws {
        let drawn = [CGPoint(x: 40, y: 40), CGPoint(x: 160, y: 260), CGPoint(x: 300, y: 60)]
        let corners = try #require(corners(of: ShapeRecognizer.shape(for: Hand.line(through: drawn)), closed: false))
        #expect(match(corners, drawn))
    }

    @Test(arguments: [0.6, 1, 1.3, 1.6] as [CGFloat])
    func anArcIsNoShape(halfTurns: CGFloat) {
        let arc = Hand.ellipse(center: CGPoint(x: 200, y: 200), semiAxes: CGSize(width: 120, height: 120), sweep: halfTurns * .pi)
        #expect(ShapeRecognizer.shape(for: arc) == nil)
    }

    @Test func aScribbleIsNoShape() {
        let scribble = (0...200).map { step in
            let t = CGFloat(step) / 200
            return CGPoint(x: 400 * t, y: 100 + 60 * sin(t * 9 * .pi))
        }
        #expect(ShapeRecognizer.shape(for: scribble) == nil)
    }

    @Test func aPointIsNoShape() {
        #expect(ShapeRecognizer.shape(for: [CGPoint(x: 5, y: 5)]) == nil)
        #expect(ShapeRecognizer.shape(for: [CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5)]) == nil)
    }

    @Test(arguments: [80, 150, 400] as [CGFloat])
    func aRoundLineBecomesACircle(radius: CGFloat) throws {
        let center = CGPoint(x: 500, y: 500)
        let drawn = Hand.ellipse(center: center, semiAxes: CGSize(width: radius, height: radius * 0.93), waver: radius / 50)
        guard case .ellipse(let found, let semiAxes, _) = ShapeRecognizer.shape(for: drawn) else {
            Issue.record("not an ellipse")
            return
        }
        #expect(isNear(found, center, within: radius / 10))
        #expect(semiAxes.width == semiAxes.height)
        #expect(abs(semiAxes.width - radius) < radius / 10)
    }

    @Test func aCircleDrawnPastItsStartIsACircle() {
        let drawn = Hand.ellipse(center: CGPoint(x: 300, y: 300), semiAxes: CGSize(width: 100, height: 100), sweep: 2.15 * .pi)
        guard case .ellipse = ShapeRecognizer.shape(for: drawn) else {
            Issue.record("not an ellipse")
            return
        }
    }

    @Test func aFlatRoundLineBecomesAnUprightEllipse() {
        let drawn = Hand.ellipse(center: CGPoint(x: 300, y: 300), semiAxes: CGSize(width: 200, height: 90), rotation: 0.1)
        guard case .ellipse(_, let semiAxes, let rotation) = ShapeRecognizer.shape(for: drawn) else {
            Issue.record("not an ellipse")
            return
        }
        #expect(rotation == 0)
        #expect(abs(semiAxes.width - 200) < 15)
        #expect(abs(semiAxes.height - 90) < 15)
    }

    @Test func aSlantedEllipseKeepsItsSlant() {
        let drawn = Hand.ellipse(center: CGPoint(x: 300, y: 300), semiAxes: CGSize(width: 200, height: 80), rotation: 0.7)
        guard case .ellipse(_, _, let rotation) = ShapeRecognizer.shape(for: drawn) else {
            Issue.record("not an ellipse")
            return
        }
        #expect(abs(rotation - 0.7) < 0.1)
    }

    @Test func threeSidesBecomeATriangle() throws {
        let drawn = [CGPoint(x: 200, y: 50), CGPoint(x: 380, y: 330), CGPoint(x: 40, y: 300)]
        let corners = try #require(corners(of: ShapeRecognizer.shape(for: Hand.closedLine(through: drawn)), closed: true))
        #expect(match(corners, drawn, within: 12))
    }

    @Test func aTrianglesNearlyLevelBaseBecomesLevel() throws {
        let drawn = [CGPoint(x: 200, y: 50), CGPoint(x: 380, y: 310), CGPoint(x: 40, y: 300)]
        let corners = try #require(corners(of: ShapeRecognizer.shape(for: Hand.closedLine(through: drawn)), closed: true))
        #expect(Set(corners.map(\.y)).count == 2)
    }

    @Test func fourSidesAtRightAnglesBecomeAnUprightRectangle() throws {
        let drawn = [CGPoint(x: 50, y: 60), CGPoint(x: 400, y: 72), CGPoint(x: 392, y: 250), CGPoint(x: 44, y: 240)]
        let corners = try #require(corners(of: ShapeRecognizer.shape(for: Hand.closedLine(through: drawn)), closed: true))
        #expect(corners.count == 4)
        #expect(Set(corners.map(\.x)).count == 2)
        #expect(Set(corners.map(\.y)).count == 2)
        #expect(match(corners, drawn, within: 16))
    }

    @Test func aNearlySquareRectangleBecomesASquare() throws {
        let drawn = [CGPoint(x: 100, y: 100), CGPoint(x: 310, y: 100), CGPoint(x: 310, y: 295), CGPoint(x: 100, y: 295)]
        let corners = try #require(corners(of: ShapeRecognizer.shape(for: Hand.closedLine(through: drawn)), closed: true))
        #expect(corners.count == 4)
        #expect(abs(corners[0].distance(to: corners[1]) - corners[1].distance(to: corners[2])) < 0.001)
    }

    @Test func aTurnedRectangleKeepsItsTurnAndGetsRightAngles() throws {
        let turn = CGAffineTransform(translationX: 300, y: 300).rotated(by: 0.5)
        let drawn = [CGPoint(x: -150, y: -80), CGPoint(x: 150, y: -70), CGPoint(x: 145, y: 80), CGPoint(x: -150, y: 80)].map { $0.applying(turn) }
        let corners = try #require(corners(of: ShapeRecognizer.shape(for: Hand.closedLine(through: drawn)), closed: true))
        #expect(match(corners, drawn, within: 16))
        let first = CGVector(dx: corners[1].x - corners[0].x, dy: corners[1].y - corners[0].y)
        let second = CGVector(dx: corners[2].x - corners[1].x, dy: corners[2].y - corners[1].y)
        #expect(abs(first.dx * second.dx + first.dy * second.dy) < 0.001)
    }

    @Test func fourSlantedSidesStayAsDrawn() throws {
        let drawn = [CGPoint(x: 120, y: 60), CGPoint(x: 420, y: 60), CGPoint(x: 340, y: 240), CGPoint(x: 40, y: 240)]
        let corners = try #require(corners(of: ShapeRecognizer.shape(for: Hand.closedLine(through: drawn)), closed: true))
        #expect(match(corners, drawn, within: 12))
    }

    @Test func fiveSidesBecomeAPentagon() throws {
        let drawn = (0..<5).map { corner in
            let angle = -CGFloat.pi / 2 + 2 * .pi * CGFloat(corner) / 5
            return CGPoint(x: 300 + 160 * cos(angle), y: 300 + 160 * sin(angle))
        }
        let corners = try #require(corners(of: ShapeRecognizer.shape(for: Hand.closedLine(through: drawn)), closed: true))
        #expect(match(corners, drawn, within: 12))
    }

    @Test func aRectangleWithRoundCornersGetsSharpOnes() throws {
        let drawn = [CGPoint(x: 50, y: 50), CGPoint(x: 350, y: 50), CGPoint(x: 350, y: 250), CGPoint(x: 50, y: 250)]
        var line: [CGPoint] = []
        for index in 0..<4 {
            let start = drawn[index], end = drawn[(index + 1) % 4], next = drawn[(index + 2) % 4]
            line += (2...18).map { start.interpolated(to: end, by: CGFloat($0) / 20) }
            // A quarter turn around the corner in place of the corner itself.
            let before = start.interpolated(to: end, by: 0.9), after = end.interpolated(to: next, by: 0.1)
            line += (1..<6).map { step in
                let t = CGFloat(step) / 6
                let a = before.interpolated(to: end, by: t), b = end.interpolated(to: after, by: t)
                return a.interpolated(to: b, by: t)
            }
        }
        let corners = try #require(corners(of: ShapeRecognizer.shape(for: line), closed: true))
        #expect(match(corners, drawn, within: 6))
    }

    @Test func theSplineOfAPolylineTurnsSharplyAtEveryCorner() {
        let shape = RecognizedShape.polyline(corners: [.zero, CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)], isClosed: true)
        let points = shape.splineControlPoints(spacing: 4)
        for corner in [CGPoint.zero, CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)] {
            #expect(points.count { $0 == corner } >= 3)
        }
        #expect(points.first == points.last)
        #expect(zip(points, points.dropFirst()).allSatisfy { $0.distance(to: $1) <= 4.001 })
    }

    @Test func theSplineOfAnEllipseClosesOnItself() {
        let shape = RecognizedShape.ellipse(center: CGPoint(x: 50, y: 50), semiAxes: CGSize(width: 40, height: 20), rotation: 0)
        let points = shape.splineControlPoints(spacing: 5)
        #expect(points.count >= 24)
        #expect(points.allSatisfy { abs(hypot(($0.x - 50) / 40, ($0.y - 50) / 20) - 1) < 0.001 })
        #expect(points[0].distance(to: points[points.count - 3]) < 0.001)
    }
}
