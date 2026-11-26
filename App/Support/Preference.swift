import Foundation

/// Keys of the settings kept in user defaults.
nonisolated enum Preference {
    static let allowsFingerDrawing = "allowsFingerDrawing"
    static let librarySortOrder = "librarySortOrder"
    static let lastPaperTemplate = "lastPaperTemplate"
    static let toolSettings = "toolSettings"
    static let toolBarEdge = "toolBarEdge"

    /// The Simulator has no Apple Pencil, so drawing there needs a finger or the pointer.
    static var allowsFingerDrawingByDefault: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
