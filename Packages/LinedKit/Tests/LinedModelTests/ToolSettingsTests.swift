import Foundation
import Testing
@testable import LinedModel

struct ToolSettingsTests {
    @Test func startsWithThePen() {
        #expect(ToolSettings().tool == .pen)
    }

    @Test func remembersTheToolUsedBefore() {
        var settings = ToolSettings()
        settings.select(.eraser)
        settings.select(.lasso)

        settings.selectPreviousTool()

        #expect(settings.tool == .eraser)
        #expect(settings.previousTool == .lasso)
    }

    @Test func selectingTheCurrentToolKeepsThePreviousOne() {
        var settings = ToolSettings()
        settings.select(.lasso)

        settings.select(.lasso)

        #expect(settings.previousTool == .pen)
    }

    @Test func togglingTheEraserReturnsToTheToolBeforeIt() {
        var settings = ToolSettings()
        settings.select(.lasso)

        settings.toggleEraser()
        #expect(settings.tool == .eraser)

        settings.toggleEraser()
        #expect(settings.tool == .lasso)

        settings.toggleEraser()
        #expect(settings.tool == .eraser)
    }

    @Test func theEraserHandsOverAfterErasingOnlyWhenSetUpTo() {
        var settings = ToolSettings()
        settings.select(.eraser)

        settings.finishErasing()
        #expect(settings.tool == .pen)

        settings.returnsAfterErasing = false
        settings.select(.eraser)
        settings.finishErasing()
        #expect(settings.tool == .eraser)
    }

    @Test func finishingToEraseLeavesOtherToolsAlone() {
        var settings = ToolSettings()
        settings.select(.lasso)

        settings.finishErasing()

        #expect(settings.tool == .lasso)
    }

    @Test func widthsGrowFromFineToBold() {
        var settings = ToolSettings()
        let penWidths = StrokeWidth.allCases.map { width in
            settings.penWidth = width
            return settings.penLineWidth
        }
        #expect(penWidths == penWidths.sorted() && Set(penWidths).count == penWidths.count)
        let eraserWidths = StrokeWidth.allCases.map { width in
            settings.eraserWidth = width
            return settings.eraserDiameter
        }
        #expect(eraserWidths == eraserWidths.sorted() && Set(eraserWidths).count == eraserWidths.count)
    }

    @Test func everyColourIsAValidColour() {
        for color in InkColor.allCases {
            let (red, green, blue) = color.components
            #expect([red, green, blue].allSatisfy { (0...1).contains($0) })
        }
    }

    @Test func survivesBeingSavedAndRead() throws {
        var settings = ToolSettings()
        settings.select(.lasso)
        settings.penColor = .blue
        settings.penWidth = .bold
        settings.eraserWidth = .bold
        settings.returnsAfterErasing = false

        let read = try JSONDecoder().decode(ToolSettings.self, from: JSONEncoder().encode(settings))

        #expect(read == settings)
    }
}
