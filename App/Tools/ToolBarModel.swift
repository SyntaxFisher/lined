import Foundation
import LinedLayout
import LinedModel
import Observation

/// What a double tap on Apple Pencil asks the tools to do.
enum PencilShortcut {
    case toggleEraser
    case selectPreviousTool
    case toggleOptions
}

/// The tools of the notebook editor and the place of their bar, kept across launches.
@Observable
final class ToolBarModel {
    var settings: ToolSettings {
        didSet {
            if settings != oldValue {
                defaults.set(try? JSONEncoder().encode(settings), forKey: Preference.toolSettings)
            }
        }
    }

    var edge: DockEdge {
        didSet { defaults.set(edge.rawValue, forKey: Preference.toolBarEdge) }
    }

    /// Whether the bar shows the options of the selected tool.
    var isShowingOptions = false

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Preference.toolSettings)
        settings = stored.flatMap { try? JSONDecoder().decode(ToolSettings.self, from: $0) } ?? ToolSettings()
        edge = defaults.string(forKey: Preference.toolBarEdge).flatMap(DockEdge.init) ?? .bottom
    }

    /// Selects a tool and shows its options. A tap on the tool that is already selected shows or hides them.
    func tap(_ tool: DrawingTool) {
        if tool == settings.tool {
            isShowingOptions = tool.hasOptions && !isShowingOptions
        } else {
            settings.select(tool)
            isShowingOptions = tool.hasOptions
        }
    }

    func perform(_ shortcut: PencilShortcut) {
        switch shortcut {
        case .toggleEraser: settings.toggleEraser()
        case .selectPreviousTool: settings.selectPreviousTool()
        case .toggleOptions: isShowingOptions = settings.tool.hasOptions && !isShowingOptions
        }
        isShowingOptions = isShowingOptions && settings.tool.hasOptions
    }
}

extension DrawingTool {
    var hasOptions: Bool { self != .lasso }
}
