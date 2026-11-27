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
    @State private var toolBar = ToolBarModel()

    var body: some View {
        canvas
            .overlay {
                FloatingToolBar(model: toolBar)
            }
            .navigationTitle(title)
            .toolbarTitleMenu {
                RenameButton()
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Undo", systemImage: "arrow.uturn.backward", action: session.undo)
                        .disabled(!session.canUndo)
                        .keyboardShortcut("z", modifiers: .command)
                    Button("Redo", systemImage: "arrow.uturn.forward", action: session.redo)
                        .disabled(!session.canRedo)
                        .keyboardShortcut("z", modifiers: [.command, .shift])
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
            .overlay {
                if session.isImporting {
                    ProgressView("Importing…")
                        .padding(24)
                        .background(.regularMaterial, in: .rect(cornerRadius: 16))
                }
            }
            .alert("The PDF could not be imported", isPresented: $session.importFailureMessage.isPresent) {
                Button("OK") {}
            } message: {
                Text(session.importFailureMessage ?? "")
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

    private var canvas: some View {
        NotebookCanvas(
            session: session,
            tools: toolBar.settings,
            allowsFingerDrawing: allowsFingerDrawing,
            onToolBegin: {
                // Writing takes the options out of the way.
                if toolBar.isShowingOptions {
                    toolBar.isShowingOptions = false
                }
            },
            onEraseEnd: { toolBar.settings.finishErasing() },
            onPencilShortcut: toolBar.perform
        )
        // The canvas keeps its size when a keyboard comes up: PencilKit drops a lasso selection
        // whenever its view is resized.
        .ignoresSafeArea(.all, edges: [.horizontal, .bottom])
    }

    private var title: Binding<String> {
        Binding {
            library.library.notebook(session.notebookID)?.title ?? ""
        } set: { newTitle in
            library.perform { try library.rename(.notebook(session.notebookID), to: newTitle) }
        }
    }
}

/// Adds pages: a page of paper, or the pages of a PDF.
struct AddPageMenu<Label: View>: View {
    let session: NotebookSession
    var placement = NotebookSession.PagePlacement.afterCurrentPage
    @ViewBuilder let label: Label

    @State private var isChoosingPDF = false

    var body: some View {
        Menu {
            ForEach(PaperTemplate.allCases, id: \.self) { template in
                Button(template.displayName, systemImage: template.symbolName) {
                    Task { await session.addPage(template: template, placement: placement) }
                }
            }
            Divider()
            Button("Import PDF…", systemImage: "arrow.down.doc") { isChoosingPDF = true }
        } label: {
            label
        }
        .fileImporter(isPresented: $isChoosingPDF, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await session.importPDFs(from: urls, placement: placement) }
            }
        }
    }
}

extension AddPageMenu where Label == SwiftUI.Label<Text, Image> {
    /// The tool bar button, which adds pages after the current one.
    init(session: NotebookSession) {
        self.init(session: session) {
            SwiftUI.Label("Add Page", systemImage: "plus.rectangle.portrait")
        }
    }
}
