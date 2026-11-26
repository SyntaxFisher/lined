import Foundation
import Testing
@testable import LinedModel

struct ToolSettingsTests {
    @Test func startsWithThePen() {
        #expect(ToolSettings().tool == .pen)
    }

    @Test func remembersTheToolUsedBefore() {
        var settings = ToolSettings()
        settings.select(.highlighter)
        settings.select(.lasso)

        settings.selectPreviousTool()

        #expect(settings.tool == .highlighter)
        #expect(settings.previousTool == .lasso)
    }

    @Test func selectingTheCurrentToolKeepsThePreviousOne() {
        var settings = ToolSettings()
        settings.select(.highlighter)

        settings.select(.highlighter)

        #expect(settings.previousTool == .pen)
    }

    @Test func togglingTheEraserReturnsToTheToolBeforeIt() {
        var settings = ToolSettings()
        settings.select(.highlighter)

        settings.toggleEraser()
        #expect(settings.tool == .eraser)

        settings.toggleEraser()
        #expect(settings.tool == .highlighter)

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
        for style in ToolSettings.PenStyle.allCases {
            settings.penStyle = style
            let widths = StrokeWidth.allCases.map { width in
                settings.penWidth = width
                return settings.penLineWidth
            }
            #expect(widths == widths.sorted() && Set(widths).count == widths.count)
        }
        let highlighterWidths = StrokeWidth.allCases.map { width in
            settings.highlighterWidth = width
            return settings.highlighterLineWidth
        }
        #expect(highlighterWidths == highlighterWidths.sorted() && Set(highlighterWidths).count == highlighterWidths.count)
    }

    @Test func everyColourIsOfferedExactlyOnceAndIsAValidColour() {
        #expect((InkColor.penPalette + InkColor.highlighterPalette).sorted { $0.rawValue < $1.rawValue } == InkColor.allCases.sorted { $0.rawValue < $1.rawValue })
        for color in InkColor.allCases {
            let (red, green, blue) = color.components
            #expect([red, green, blue].allSatisfy { (0...1).contains($0) })
        }
    }

    @Test func survivesBeingSavedAndRead() throws {
        var settings = ToolSettings()
        settings.select(.highlighter)
        settings.penColor = .blue
        settings.penStyle = .fineliner
        settings.highlighterWidth = .bold
        settings.eraserMode = .precise
        settings.returnsAfterErasing = false

        let read = try JSONDecoder().decode(ToolSettings.self, from: JSONEncoder().encode(settings))

        #expect(read == settings)
    }
}
