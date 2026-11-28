import LinedModel
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Imports the PDFs other apps share with Lined, through the share sheet or "Open in".
    func importsSharedPDFs(navigator: LibraryNavigator) -> some View {
        modifier(SharedPDFImport(navigator: navigator))
    }
}

/// A shared PDF becomes a new notebook in the folder the reader is looking at, and the notebook
/// opens. While a notebook is open, the reader chooses between adding the pages to it and a new
/// notebook beside it.
///
/// The system hands each PDF over as a copy in an inbox of the app, which is removed once the PDF
/// has been imported or declined.
private struct SharedPDFImport: ViewModifier {
    let navigator: LibraryNavigator

    @Environment(LibraryModel.self) private var library
    @State private var waiting: [URL] = []
    @State private var isChoosing = false
    @State private var isImporting = false

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                receive(url)
            }
            .alert(choiceTitle, isPresented: $isChoosing) {
                Button("Add to Notebook") {
                    navigator.pdfsForOpenNotebook += waiting
                    waiting = []
                }
                Button(waiting.count == 1 ? "New Notebook" : "New Notebooks") {
                    let folderID = navigator.openNotebookID.flatMap { library.library.notebook($0)?.folderID }
                    Task { await importAsNotebooks(into: folderID) }
                }
                Button("Cancel", role: .cancel) {
                    waiting.forEach(SharedPDF.discard)
                    waiting = []
                }
            } message: {
                Text(choiceMessage)
            }
            .overlay {
                if isImporting {
                    ProgressView("Importing…")
                        .padding(24)
                        .background(.regularMaterial, in: .rect(cornerRadius: 16))
                }
            }
    }

    private var choiceTitle: String {
        waiting.count == 1 ? String(localized: "Import PDF") : String(localized: "Import \(waiting.count) PDFs")
    }

    private var choiceMessage: String {
        let title = navigator.openNotebookID.flatMap { library.library.notebook($0)?.title } ?? ""
        return String(localized: "Add the pages to “\(title)” after the current page, or make a new notebook?")
    }

    private func receive(_ url: URL) {
        guard url.isFileURL, UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true else { return }
        waiting.append(url)
        if navigator.openNotebookID != nil {
            isChoosing = true
        } else if !isImporting {
            Task { await importAsNotebooks(into: navigator.currentFolderID) }
        }
    }

    /// Imports each waiting PDF as its own notebook and opens the notebook when there is just one.
    private func importAsNotebooks(into folderID: Folder.ID?) async {
        isImporting = true
        defer { isImporting = false }
        var received = 0
        var imported: [Notebook] = []
        while !waiting.isEmpty {
            let url = waiting.removeFirst()
            received += 1
            do {
                imported.append(try await library.importPDF(from: url, into: folderID))
            } catch {
                library.failureMessage = ErrorMessage.text(for: error)
            }
            SharedPDF.discard(url)
        }
        if received == 1, let notebook = imported.first {
            navigator.show(notebook.id)
        }
    }
}

enum SharedPDF {
    /// Removes the copy the system made of a shared PDF. A file outside the app's inboxes is left alone.
    static func discard(_ url: URL) {
        let inboxes = [
            URL.temporaryDirectory.appending(path: "\(Bundle.main.bundleIdentifier ?? "")-Inbox", directoryHint: .isDirectory),
            URL.documentsDirectory.appending(path: "Inbox", directoryHint: .isDirectory),
        ]
        let path = url.resolvingSymlinksInPath().path()
        guard inboxes.contains(where: { path.hasPrefix($0.resolvingSymlinksInPath().path()) }) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
