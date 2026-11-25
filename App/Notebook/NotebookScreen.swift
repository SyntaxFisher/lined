import LinedModel
import SwiftUI

/// Opens a notebook and shows its editor.
struct NotebookScreen: View {
    let notebookID: Notebook.ID

    @Environment(AppEnvironment.self) private var environment
    @State private var session: NotebookSession?
    @State private var failure: String?

    var body: some View {
        Group {
            if let session {
                NotebookEditor(session: session)
            } else if let failure {
                ContentUnavailableView(
                    "This notebook can't be opened",
                    systemImage: "exclamationmark.triangle",
                    description: Text(failure)
                )
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard session == nil else { return }
            do {
                session = try await environment.openNotebook(notebookID)
            } catch {
                failure = ErrorMessage.text(for: error)
            }
        }
    }
}

private struct NotebookEditor: View {
    @Bindable var session: NotebookSession

    @Environment(LibraryModel.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Preference.allowsFingerDrawing) private var allowsFingerDrawing = Preference.allowsFingerDrawingByDefault
    @State private var isShowingPages = false

    var body: some View {
        NotebookCanvas(session: session, allowsFingerDrawing: allowsFingerDrawing, isToolPickerVisible: !isShowingPages)
            .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
            .ignoresSafeArea(.keyboard)
            .navigationTitle(title)
            .toolbarTitleMenu {
                RenameButton()
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Undo", systemImage: "arrow.uturn.backward", action: session.undoManager.undo)
                        .disabled(!session.canUndo)
                    Button("Redo", systemImage: "arrow.uturn.forward", action: session.undoManager.redo)
                        .disabled(!session.canRedo)
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Toggle("Draw with Finger", systemImage: "hand.draw", isOn: $allowsFingerDrawing)
                    AddPageMenu(session: session)
                    Button {
                        isShowingPages = true
                    } label: {
                        Text("\(session.currentPageIndex + 1) of \(session.pages.count)")
                            .monospacedDigit()
                    }
                    .accessibilityLabel("Pages")
                    .accessibilityValue("Page \(session.currentPageIndex + 1) of \(session.pages.count)")
                }
            }
            .sheet(isPresented: $isShowingPages) {
                PageOverview(session: session)
            }
            .alert("Your changes could not be saved", isPresented: $session.failureMessage.isPresent) {
                Button("OK") {}
            } message: {
                Text(session.failureMessage ?? "")
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    Task { await session.save() }
                }
            }
            .onDisappear {
                Task { await session.save() }
            }
    }

    private var title: Binding<String> {
        Binding {
            library.library.notebook(session.notebookID)?.title ?? ""
        } set: { newTitle in
            library.perform { try library.rename(.notebook(session.notebookID), to: newTitle) }
        }
    }
}

/// Adds a page after the current one: a tap continues the current paper, the menu offers the others.
struct AddPageMenu: View {
    let session: NotebookSession

    var body: some View {
        Menu("Add Page", systemImage: "plus.rectangle.portrait") {
            ForEach(PaperTemplate.allCases, id: \.self) { template in
                Button(template.displayName, systemImage: template.symbolName) {
                    Task { await session.addPage(template: template) }
                }
            }
        } primaryAction: {
            Task { await session.addPage() }
        }
    }
}
