import LinedModel
import SwiftUI

/// The options of the selected tool, as they unfold inside the tool bar.
struct ToolOptions: View {
    @Binding var settings: ToolSettings
    /// Whether the options stand in a column, for a bar at the side of the canvas.
    let isColumn: Bool

    var body: some View {
        let stack = isColumn ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        stack {
            switch settings.tool {
            case .pen:
                ColorChoices(colors: InkColor.penPalette, selection: $settings.penColor, isColumn: isColumn)
                ToolBarSeparator(isAcross: isColumn)
                WidthChoices(selection: $settings.penWidth, color: Color(settings.penColor), isColumn: isColumn)
                ToolBarSeparator(isAcross: isColumn)
                choices(ToolSettings.PenStyle.allCases, selection: $settings.penStyle)
            case .highlighter:
                ColorChoices(colors: InkColor.highlighterPalette, selection: $settings.highlighterColor, isColumn: isColumn)
                ToolBarSeparator(isAcross: isColumn)
                WidthChoices(selection: $settings.highlighterWidth, color: Color(settings.highlighterColor), isColumn: isColumn)
            case .eraser:
                textChoices(ToolSettings.EraserMode.allCases, selection: $settings.eraserMode)
                if settings.eraserMode == .precise {
                    ToolBarSeparator(isAcross: isColumn)
                    WidthChoices(selection: $settings.eraserWidth, color: .secondary, isColumn: isColumn)
                }
                ToolBarSeparator(isAcross: isColumn)
                Toggle(isOn: $settings.returnsAfterErasing) {
                    Label("Switch Back", systemImage: "arrow.uturn.backward")
                        .labelStyle(isColumn ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                }
                .toggleStyle(ToolBarToggleStyle())
                .accessibilityLabel("Switch back after erasing")
            case .lasso:
                EmptyView()
            }
        }
    }

    /// Choices named in words, for options whose difference a small icon does not show.
    private func textChoices<Choice: TextChoice>(_ all: [Choice], selection: Binding<Choice>) -> some View {
        let stack = isColumn ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        return stack {
            ForEach(all, id: \.self) { choice in
                let isSelected = choice == selection.wrappedValue
                Button {
                    selection.wrappedValue = choice
                } label: {
                    Text(choice.title)
                        .font(isColumn ? .caption.weight(.semibold) : .subheadline.weight(.medium))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .padding(.horizontal, isColumn ? 6 : 10)
                        .frame(minWidth: 36, minHeight: 36)
                        .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.displayName)
                .accessibilityInputLabels([choice.title])
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func choices<Choice: ToolChoice>(_ all: [Choice], selection: Binding<Choice>) -> some View {
        let stack = isColumn ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        return stack {
            ForEach(all, id: \.self) { choice in
                Button {
                    selection.wrappedValue = choice
                } label: {
                    ToolBarIcon(systemName: choice.symbolName, isSelected: choice == selection.wrappedValue, diameter: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.displayName)
                .accessibilityAddTraits(choice == selection.wrappedValue ? .isSelected : [])
            }
        }
    }
}

private struct ColorChoices: View {
    let colors: [InkColor]
    @Binding var selection: InkColor
    let isColumn: Bool

    var body: some View {
        // At the side of the canvas the colours stand two abreast, which keeps the bar short.
        let columns = isColumn ? 2 : colors.count
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(Array(stride(from: 0, to: colors.count, by: columns)), id: \.self) { start in
                GridRow {
                    ForEach(colors[start..<min(start + columns, colors.count)], id: \.self) { color in
                        swatch(color)
                    }
                }
            }
        }
    }

    private func swatch(_ color: InkColor) -> some View {
        Button {
            selection = color
        } label: {
            InkDot(color: Color(color))
                .frame(width: 24, height: 24)
                .padding(4)
                .overlay {
                    if color == selection {
                        Circle().strokeBorder(.primary, lineWidth: 2)
                    }
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.displayName)
        .accessibilityAddTraits(color == selection ? .isSelected : [])
    }
}

private struct WidthChoices: View {
    @Binding var selection: StrokeWidth
    /// The colour the tool writes in.
    let color: Color
    let isColumn: Bool

    var body: some View {
        let stack = isColumn ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        stack {
            ForEach(StrokeWidth.allCases, id: \.self) { width in
                Button {
                    selection = width
                } label: {
                    InkDot(color: color)
                        .frame(width: width.dotDiameter, height: width.dotDiameter)
                        .frame(width: 32, height: 32)
                        .overlay {
                            if width == selection {
                                Circle().strokeBorder(.primary, lineWidth: 2)
                            }
                        }
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(width.displayName)
                .accessibilityAddTraits(width == selection ? .isSelected : [])
            }
        }
    }
}

/// A dot of ink colour, edged so that dark ink stays visible on the dark bar and light ink on the light one.
private struct InkDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .strokeBorder(.primary.opacity(0.25), lineWidth: 1)
    }
}

/// A choice the tool bar offers as a round icon.
private protocol ToolChoice: Hashable {
    var symbolName: String { get }
    var displayName: LocalizedStringKey { get }
}

extension ToolSettings.PenStyle: ToolChoice {
    fileprivate var symbolName: String {
        switch self {
        case .pen: "scribble.variable"
        case .fineliner: "scribble"
        }
    }

    fileprivate var displayName: LocalizedStringKey {
        switch self {
        case .pen: "Pen that follows pressure"
        case .fineliner: "Fineliner with an even line"
        }
    }
}

/// A choice the tool bar offers as a word.
private protocol TextChoice: Hashable {
    var title: LocalizedStringKey { get }
    var displayName: LocalizedStringKey { get }
}

extension ToolSettings.EraserMode: TextChoice {
    fileprivate var title: LocalizedStringKey {
        switch self {
        case .stroke: "Stroke"
        case .precise: "Pixel"
        }
    }

    fileprivate var displayName: LocalizedStringKey {
        switch self {
        case .stroke: "Erase whole strokes"
        case .precise: "Erase precisely"
        }
    }
}

private extension StrokeWidth {
    var dotDiameter: CGFloat {
        switch self {
        case .fine: 6
        case .medium: 10
        case .bold: 15
        }
    }

    var displayName: LocalizedStringKey {
        switch self {
        case .fine: "Fine"
        case .medium: "Medium"
        case .bold: "Bold"
        }
    }
}

private extension InkColor {
    var displayName: LocalizedStringKey {
        switch self {
        case .black: "Black"
        case .gray: "Gray"
        case .blue: "Blue"
        case .green: "Green"
        case .orange: "Orange"
        case .red: "Red"
        case .purple: "Purple"
        case .brown: "Brown"
        case .yellow: "Yellow"
        case .mint: "Mint"
        case .sky: "Sky Blue"
        case .pink: "Pink"
        case .peach: "Peach"
        case .lilac: "Lilac"
        }
    }
}

/// A toggle of the tool bar, filled like a selected tool while it is on.
private struct ToolBarToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .font(.subheadline.weight(.medium))
                .foregroundStyle(configuration.isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 10)
                .frame(minWidth: 36, minHeight: 36)
                .background(configuration.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

/// Lets a label switch between styles of different types.
private struct AnyLabelStyle: LabelStyle {
    private let body: (Configuration) -> AnyView

    init(_ style: some LabelStyle) {
        body = { AnyView(Label($0).labelStyle(style)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        body(configuration)
    }
}
