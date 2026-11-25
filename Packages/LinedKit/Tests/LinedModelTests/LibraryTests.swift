import Foundation
import Testing
@testable import LinedModel

struct LibraryTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func date(_ offset: TimeInterval) -> Date { start.addingTimeInterval(offset) }

    @Test func createsNestedFoldersAndNotebooks() throws {
        var library = Library()
        let semester = try library.createFolder(named: "  Semester 3 ", in: nil, at: date(0))
        let maths = try library.createFolder(named: "Maths", in: semester.id, at: date(1))
        let notes = try library.addNotebook(titled: "Lecture notes", in: maths.id, at: date(2))

        #expect(semester.name == "Semester 3")
        #expect(library.path(to: maths.id).map(\.name) == ["Semester 3", "Maths"])
        #expect(library.contents(of: maths.id, sortedBy: .name) == [.notebook(notes)])
        #expect(library.itemCount(in: semester.id) == 1)
        #expect(library.folder(maths.id)?.modifiedAt == date(2))
    }

    @Test func rejectsEmptyNamesAndUnknownParents() {
        var library = Library()
        #expect(throws: LibraryError.emptyName) { try library.createFolder(named: " \n", in: nil) }
        #expect(throws: LibraryError.emptyName) { try library.addNotebook(titled: "", in: nil) }
        #expect(throws: LibraryError.folderNotFound) { try library.createFolder(named: "Lost", in: Folder.ID()) }
        #expect(library.folders.isEmpty)
    }

    @Test func sortsFoldersFirstAndNamesNaturally() throws {
        var library = Library()
        try library.addNotebook(titled: "Page 10", in: nil, at: date(0))
        try library.addNotebook(titled: "page 2", in: nil, at: date(1))
        try library.createFolder(named: "Zoology", in: nil, at: date(2))
        try library.createFolder(named: "Algebra", in: nil, at: date(3))

        let names = library.contents(of: nil, sortedBy: .name).map(\.name)
        #expect(names == ["Algebra", "Zoology", "page 2", "Page 10"])
    }

    @Test func sortsByDatesNewestFirst() throws {
        var library = Library()
        let old = try library.addNotebook(titled: "Old", in: nil, at: date(0))
        let new = try library.addNotebook(titled: "New", in: nil, at: date(10))
        #expect(library.contents(of: nil, sortedBy: .dateCreated).map(\.name) == ["New", "Old"])

        library.markNotebookModified(old.id, at: date(20))
        #expect(library.contents(of: nil, sortedBy: .dateModified).map(\.name) == ["Old", "New"])
        #expect(library.notebook(new.id)?.modifiedAt == date(10))
    }

    @Test func renamesItems() throws {
        var library = Library()
        let folder = try library.createFolder(named: "Draft", in: nil, at: date(0))
        let notebook = try library.addNotebook(titled: "Draft", in: folder.id, at: date(0))

        try library.rename(.folder(folder.id), to: "Final", at: date(5))
        try library.rename(.notebook(notebook.id), to: "Summary", at: date(5))

        #expect(library.folder(folder.id)?.name == "Final")
        #expect(library.notebook(notebook.id)?.title == "Summary")
        #expect(library.notebook(notebook.id)?.modifiedAt == date(0))
        #expect(throws: LibraryError.emptyName) { try library.rename(.folder(folder.id), to: " ") }
        #expect(throws: LibraryError.notebookNotFound) { try library.rename(.notebook(Notebook.ID()), to: "x") }
    }

    @Test func movesItemsBetweenFolders() throws {
        var library = Library()
        let source = try library.createFolder(named: "Source", in: nil, at: date(0))
        let target = try library.createFolder(named: "Target", in: nil, at: date(0))
        let notebook = try library.addNotebook(titled: "Notes", in: source.id, at: date(0))

        try library.move(.notebook(notebook.id), to: target.id, at: date(9))
        try library.move(.folder(source.id), to: target.id, at: date(9))

        #expect(library.contents(of: target.id, sortedBy: .name).map(\.name) == ["Source", "Notes"])
        #expect(library.contents(of: nil, sortedBy: .name).map(\.name) == ["Target"])
        #expect(library.folder(target.id)?.modifiedAt == date(9))
    }

    @Test func refusesToMoveAFolderIntoItsOwnSubtree() throws {
        var library = Library()
        let outer = try library.createFolder(named: "Outer", in: nil)
        let inner = try library.createFolder(named: "Inner", in: outer.id)

        #expect(!library.canMove(.folder(outer.id), to: inner.id))
        #expect(!library.canMove(.folder(outer.id), to: outer.id))
        #expect(library.canMove(.folder(inner.id), to: nil))
        #expect(throws: LibraryError.folderCannotContainItself) { try library.move(.folder(outer.id), to: inner.id) }
        #expect(library.folder(outer.id)?.parentID == nil)
    }

    @Test func deletingAFolderRemovesEverythingInside() throws {
        var library = Library()
        let outer = try library.createFolder(named: "Outer", in: nil)
        let inner = try library.createFolder(named: "Inner", in: outer.id)
        let nested = try library.addNotebook(titled: "Nested", in: inner.id)
        let direct = try library.addNotebook(titled: "Direct", in: outer.id)
        let kept = try library.addNotebook(titled: "Kept", in: nil)

        let removed = try library.delete(.folder(outer.id))

        #expect(removed == [nested.id, direct.id])
        #expect(library.folders.isEmpty)
        #expect(library.notebooks == [kept])
    }

    @Test func listsFoldersDepthFirst() throws {
        var library = Library()
        let b = try library.createFolder(named: "B", in: nil)
        let a = try library.createFolder(named: "A", in: nil)
        try library.createFolder(named: "A2", in: a.id)
        try library.createFolder(named: "A1", in: a.id)
        try library.createFolder(named: "B1", in: b.id)

        let hierarchy = library.folderHierarchy()
        #expect(hierarchy.map(\.folder.name) == ["A", "A1", "A2", "B", "B1"])
        #expect(hierarchy.map(\.depth) == [0, 1, 1, 0, 1])
    }

    @Test func reconcileAdoptsOrphanedPackagesAndDropsMissingOnes() throws {
        var library = Library()
        let present = try library.addNotebook(titled: "Present", in: nil)
        let missing = try library.addNotebook(titled: "Missing", in: nil)
        let orphan = Notebook.ID()

        let changed = library.reconcile(storedNotebooks: [present.id, orphan], recoveredTitle: "Recovered", at: date(3))

        #expect(changed)
        #expect(library.notebook(missing.id) == nil)
        #expect(library.notebook(orphan)?.title == "Recovered")

        let changedAgain = library.reconcile(storedNotebooks: [present.id, orphan], recoveredTitle: "Recovered")
        #expect(!changedAgain)
    }

    @Test func repairsDanglingParentsAndCyclesOnLoad() {
        let first = Folder.ID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let second = Folder.ID(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let lost = Folder.ID()
        let folders = [
            Folder(id: first, name: "First", parentID: second, createdAt: date(0), modifiedAt: date(0)),
            Folder(id: second, name: "Second", parentID: first, createdAt: date(1), modifiedAt: date(1)),
            Folder(name: "Dangling", parentID: lost, createdAt: date(2), modifiedAt: date(2)),
        ]
        let notebook = Notebook(title: "Stray", folderID: lost, createdAt: date(0), modifiedAt: date(0))

        let library = Library(folders: folders, notebooks: [notebook])

        #expect(library.contents(of: nil, sortedBy: .name).map(\.name) == ["Dangling", "First", "Stray"])
        #expect(library.folder(second)?.parentID == first)
    }
}
