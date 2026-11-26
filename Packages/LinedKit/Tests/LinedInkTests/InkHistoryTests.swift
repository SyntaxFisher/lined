import Testing
@testable import LinedInk

struct InkHistoryTests {
    private typealias Change = InkChange<String, TestStroke>

    private let first = Change(pageID: "a", before: [], after: [TestStroke(1, 1)])
    private let second = Change(pageID: "a", before: [TestStroke(1, 1)], after: [TestStroke(1, 1), TestStroke(2, 2)])
    private let elsewhere = Change(pageID: "b", before: [], after: [TestStroke(3, 3)])

    @Test func startsWithNothingToUndoOrRedo() {
        var history = InkHistory<String, TestStroke>()

        #expect(!history.canUndo)
        #expect(!history.canRedo)
        #expect(history.undo() == nil)
        #expect(history.redo() == nil)
    }

    @Test func undoesTheLatestEditFirstAndRedoesItAgain() {
        var history = InkHistory<String, TestStroke>()
        history.record([first])
        history.record([second])

        let undone = history.undo()

        #expect(undone?.map(\.after) == [second.before])
        #expect(history.canUndo)
        #expect(history.canRedo)

        let redone = history.redo()

        #expect(redone?.map(\.after) == [second.after])
        #expect(!history.canRedo)
        #expect(history.undo()?.map(\.after) == [second.before])
        #expect(history.undo()?.map(\.after) == [first.before])
        #expect(!history.canUndo)
    }

    @Test func aNewEditEndsWhatCouldBeRedone() {
        var history = InkHistory<String, TestStroke>()
        history.record([first])
        _ = history.undo()

        history.record([elsewhere])

        #expect(!history.canRedo)
        #expect(history.undo()?.map(\.pageID) == ["b"])
        #expect(!history.canUndo)
    }

    @Test func anEditWithoutChangesIsNoStep() {
        var history = InkHistory<String, TestStroke>()

        history.record([])

        #expect(!history.canUndo)
    }

    @Test func keepsOnlyTheLatestStepsUpToItsLimit() {
        var history = InkHistory<String, TestStroke>(limit: 2)
        history.record([first])
        history.record([second])
        history.record([elsewhere])

        #expect(history.undo()?.map(\.pageID) == ["b"])
        #expect(history.undo()?.map(\.after) == [second.before])
        #expect(!history.canUndo)
    }

    @Test func forgetsRemovedPagesAndTheStepsThatOnlyTouchedThem() {
        var history = InkHistory<String, TestStroke>()
        history.record([first])
        history.record([second, elsewhere])
        history.record([elsewhere.reversed])
        _ = history.undo()

        history.forget(["b"])

        #expect(!history.canRedo)
        #expect(history.undo()?.map(\.pageID) == ["a"])
        #expect(history.undo()?.map(\.pageID) == ["a"])
        #expect(!history.canUndo)
    }
}
