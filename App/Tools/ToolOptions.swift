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
                ColorChoices(colors: InkColor.allCases, selection: $settings.penColor, isColumn: isColumn)
                ToolBarSeparator(isAcross: isColumn)
                WidthChoices(selection: $settings.penWidth, isColumn: isColumn)
            case .eraser:
                WidthChoices(selection: $settings.eraserWidth, isColumn: isColumn)
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
    let isColumn: Bool

    var body: some View {
        let stack = isColumn ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        stack {
            ForEach(StrokeWidth.allCases, id: \.self) { width in
                Button {
                    selection = width
                } label: {
                    // Not in the ink colour, which the colours beside it show and which can vanish on the dark bar.
                    // The bar's glass draws `Color.primary` faintly; the label colour keeps its full contrast.
                    Circle()
                        .fill(Color(uiColor: .label))
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

/// A dot of ink colour, edged so that dark ink stays visible on the dark bar.
private struct InkDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .strokeBorder(.primary.opacity(0.25), lineWidth: 1)
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
