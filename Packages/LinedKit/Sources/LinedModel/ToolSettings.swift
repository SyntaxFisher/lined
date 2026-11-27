/// A tool for working on the ink of a page.
public enum DrawingTool: String, Codable, CaseIterable, Sendable {
    case pen
    case highlighter
    case eraser
    case lasso
}

/// A colour of ink. Paper is light in every appearance, so a colour is one fixed value.
public enum InkColor: String, Codable, CaseIterable, Sendable {
    case black, gray, blue, green, orange, red, purple, brown
    case yellow, mint, sky, pink, peach, lilac

    /// The colours offered for writing.
    public static let penPalette: [InkColor] = [.black, .gray, .blue, .green, .orange, .red, .purple, .brown]
    /// The colours offered for highlighting: light enough to read the text beneath.
    public static let highlighterPalette: [InkColor] = [.yellow, .mint, .sky, .pink, .peach, .lilac]

    /// Red, green and blue in sRGB, each from 0 to 1.
    public var components: (red: Double, green: Double, blue: Double) {
        switch self {
        case .black: (0.07, 0.07, 0.08)
        case .gray: (0.45, 0.45, 0.48)
        case .blue: (0.04, 0.33, 0.80)
        case .green: (0.11, 0.55, 0.26)
        case .orange: (0.94, 0.49, 0.03)
        case .red: (0.83, 0.14, 0.14)
        case .purple: (0.50, 0.26, 0.76)
        case .brown: (0.50, 0.33, 0.20)
        case .yellow: (1.00, 0.88, 0.00)
        case .mint: (0.36, 0.89, 0.50)
        case .sky: (0.30, 0.74, 1.00)
        case .pink: (1.00, 0.45, 0.70)
        case .peach: (1.00, 0.64, 0.25)
        case .lilac: (0.72, 0.56, 1.00)
        }
    }
}

/// One of the three line widths a writing tool offers.
public enum StrokeWidth: String, Codable, CaseIterable, Sendable {
    case fine
    case medium
    case bold
}

/// The tool in use and how each tool is set up.
public struct ToolSettings: Codable, Equatable, Sendable {
    public enum EraserMode: String, Codable, CaseIterable, Sendable {
        /// Removes every stroke it touches.
        case stroke
        /// Removes only what it passes over.
        case precise
    }

    public private(set) var tool = DrawingTool.pen
    public private(set) var previousTool = DrawingTool.eraser

    public var penColor = InkColor.black
    public var penWidth = StrokeWidth.medium
    public var highlighterColor = InkColor.yellow
    public var highlighterWidth = StrokeWidth.medium
    public var eraserMode = EraserMode.stroke
    /// How wide the precise eraser is. The stroke eraser takes what it touches and has no width.
    public var eraserWidth = StrokeWidth.fine
    /// Whether the eraser hands over to the tool used before it once it has erased something.
    public var returnsAfterErasing = true

    public init() {}

    public mutating func select(_ newTool: DrawingTool) {
        guard newTool != tool else { return }
        previousTool = tool
        tool = newTool
    }

    public mutating func selectPreviousTool() {
        select(previousTool)
    }

    /// Switches between the eraser and the tool used before it.
    public mutating func toggleEraser() {
        select(tool == .eraser ? toolBeforeEraser : .eraser)
    }

    /// Hands over to the tool used before the eraser, if the eraser is set up to do so.
    public mutating func finishErasing() {
        if tool == .eraser, returnsAfterErasing {
            select(toolBeforeEraser)
        }
    }

    private var toolBeforeEraser: DrawingTool {
        previousTool == .eraser ? .pen : previousTool
    }

    /// The width of the pen's even line in page points. Each width is about 1.6 times the one below it.
    public var penLineWidth: Double {
        switch penWidth {
        case .fine: 0.31
        case .medium: 0.5
        case .bold: 0.8
        }
    }

    /// The highlighter's line width in page points.
    public var highlighterLineWidth: Double {
        switch highlighterWidth {
        case .fine: 8
        case .medium: 14
        case .bold: 22
        }
    }

    /// The diameter of the precise eraser in screen points. It erases as much of the screen at any zoom.
    public var preciseEraserDiameter: Double {
        switch eraserWidth {
        case .fine: 20
        case .medium: 40
        case .bold: 80
        }
    }
}
