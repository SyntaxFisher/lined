import LinedLayout
import LinedModel
import SwiftUI

/// The tools, floating over the pages. The bar can be dragged to any edge of the canvas and lays
/// itself out along that edge. A tap on the selected tool unfolds its options inside the bar.
struct FloatingToolBar: View {
    @Bindable var model: ToolBarModel

    @Environment(\.layoutDirection) private var layoutDirection
    @State private var dragOffset = CGSize.zero

    private static let margin: CGFloat = 12
    private static let cornerRadius: CGFloat = 28
    private static let coordinateSpace = "FloatingToolBar"
    /// Below this width a bar at the top or bottom puts the options in rows above the tools.
    private static let compactWidth: CGFloat = 760

    var body: some View {
        GeometryReader { container in
            bar(isCompact: container.size.width < Self.compactWidth)
                .offset(dragOffset)
                .highPriorityGesture(drag(in: container.size))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.edge.alignment)
                .padding(Self.margin)
        }
        .coordinateSpace(.named(Self.coordinateSpace))
    }

    private func bar(isCompact: Bool) -> some View {
        let showsOptions = model.isShowingOptions && model.settings.tool.hasOptions
        let isRow = model.edge.isHorizontal && !isCompact
        let stack = isRow ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(spacing: 10))
        let optionsComeFirst = model.edge == .bottom && !isRow

        return stack {
            if showsOptions, optionsComeFirst {
                options
                ToolBarSeparator(isAcross: true)
            }
            ToolButtons(model: model)
            if showsOptions, !optionsComeFirst {
                ToolBarSeparator(isAcross: !isRow)
                options
            }
        }
        .padding(8)
        .fixedSize()
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Self.cornerRadius))
        // Glass alone has no edge on white paper.
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: showsOptions)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: model.settings.tool)
    }

    private var options: some View {
        ToolOptions(settings: $model.settings, isColumn: !model.edge.isHorizontal)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                var drop = value.predictedEndLocation
                if layoutDirection == .rightToLeft {
                    drop.x = size.width - drop.x
                }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    model.edge = DockEdge.nearest(to: drop, in: size)
                    dragOffset = .zero
                }
            }
    }
}

private struct ToolButtons: View {
    let model: ToolBarModel

    var body: some View {
        let stack = model.edge.isHorizontal ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 6))
        stack {
            ForEach(DrawingTool.allCases, id: \.self) { tool in
                Button {
                    model.tap(tool)
                } label: {
                    ToolBarIcon(systemName: tool.symbolName, isSelected: tool == model.settings.tool)
                        .overlay(alignment: .bottom) {
                            if let color = model.settings.color(of: tool) {
                                Capsule()
                                    .fill(Color(color))
                                    .strokeBorder(.white.opacity(0.9), lineWidth: 1)
                                    .frame(width: 16, height: 5)
                                    .offset(y: -4)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tool.displayName)
                .accessibilityAddTraits(tool == model.settings.tool ? .isSelected : [])
                .accessibilityHint(tool == model.settings.tool && tool.hasOptions ? "Shows or hides the options" : "")
            }
        }
    }
}

/// A round button face of the tool bar, filled while its choice is the selected one.
struct ToolBarIcon: View {
    let systemName: String
    let isSelected: Bool
    var diameter: CGFloat = 44

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: diameter * 0.42, weight: .medium))
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(width: diameter, height: diameter)
            .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: .circle)
            .contentShape(.circle)
    }
}

/// A hairline between two groups of the tool bar.
struct ToolBarSeparator: View {
    /// Whether the line runs across the bar's width, between groups stacked on top of each other.
    let isAcross: Bool

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: isAcross ? 28 : 1, height: isAcross ? 1 : 28)
    }
}

extension Color {
    init(_ color: InkColor) {
        let (red, green, blue) = color.components
        self.init(.sRGB, red: red, green: green, blue: blue)
    }
}

extension ToolSettings {
    /// The colour a tool writes in, for the tools that have one.
    func color(of tool: DrawingTool) -> InkColor? {
        switch tool {
        case .pen: penColor
        case .highlighter: highlighterColor
        case .eraser, .lasso: nil
        }
    }
}

extension DockEdge {
    var alignment: Alignment {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}

extension DrawingTool {
    var displayName: LocalizedStringKey {
        switch self {
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .eraser: "Eraser"
        case .lasso: "Lasso"
        }
    }

    var symbolName: String {
        switch self {
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .eraser: "eraser"
        case .lasso: "lasso"
        }
    }
}
