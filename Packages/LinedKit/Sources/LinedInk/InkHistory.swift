/// The edits to a notebook's ink that can be undone and redone.
///
/// A step holds the ink of every page it touched, before and after, so it can be taken back and
/// repeated whether or not the page is on screen.
public struct InkHistory<PageID: Hashable, Stroke: InkStroke> {
    public typealias Step = [InkChange<PageID, Stroke>]

    private var undoable: [Step] = []
    private var redoable: [Step] = []
    private let limit: Int

    /// - Parameter limit: How many steps are kept. The oldest go first.
    public init(limit: Int = 100) {
        self.limit = limit
    }

    public var canUndo: Bool { !undoable.isEmpty }
    public var canRedo: Bool { !redoable.isEmpty }

    /// Notes an edit as the next step to undo. Steps that were undone can no longer be redone.
    public mutating func record(_ step: Step) {
        guard !step.isEmpty else { return }
        undoable.append(step)
        if undoable.count > limit {
            undoable.removeFirst(undoable.count - limit)
        }
        redoable.removeAll()
    }

    /// The changes that take back the latest edit, or `nil` when there is none.
    public mutating func undo() -> Step? {
        guard let step = undoable.popLast() else { return nil }
        redoable.append(step)
        return step.map(\.reversed)
    }

    /// The changes that repeat the edit undone last, or `nil` when there is none.
    public mutating func redo() -> Step? {
        guard let step = redoable.popLast() else { return nil }
        undoable.append(step)
        return step
    }

    /// Forgets what happened on pages that no longer exist, so that no step is left without effect.
    public mutating func forget(_ pageIDs: Set<PageID>) {
        func remaining(_ steps: [Step]) -> [Step] {
            steps.map { $0.filter { !pageIDs.contains($0.pageID) } }.filter { !$0.isEmpty }
        }
        undoable = remaining(undoable)
        redoable = remaining(redoable)
    }
}
