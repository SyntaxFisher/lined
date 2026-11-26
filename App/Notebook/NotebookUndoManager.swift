import Foundation

/// What the undo manager of an open notebook passes undoing and redoing on to.
protocol NotebookHistory: AnyObject {
    var canUndo: Bool { get }
    var canRedo: Bool { get }
    func undo()
    func redo()
}

/// Lets the system's undo gestures and keyboard shortcuts act on a notebook's own history.
///
/// Nothing is recorded in the manager itself. PencilKit in particular would record steps that refer
/// to the ink of one canvas, which holds only the pages near the viewport.
final class NotebookUndoManager: UndoManager {
    weak var history: (any NotebookHistory)?

    override init() {
        super.init()
        disableUndoRegistration()
    }

    override var canUndo: Bool { history?.canUndo ?? false }
    override var canRedo: Bool { history?.canRedo ?? false }

    override func undo() {
        history?.undo()
    }

    override func redo() {
        history?.redo()
    }
}
