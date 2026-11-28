import LinedModel
import SwiftUI

/// The pages of an open notebook: scrolling, zooming and handwriting.
struct NotebookCanvas: UIViewRepresentable {
    let session: NotebookSession
    let tools: ToolSettings
    var onToolBegin: () -> Void = {}
    var onEraseEnd: () -> Void = {}
    var onPencilShortcut: (PencilShortcut) -> Void = { _ in }

    func makeUIView(context: Context) -> PagedCanvasView {
        let view = PagedCanvasView()
        view.delegate = session
        session.attach(view)
        return view
    }

    func updateUIView(_ view: PagedCanvasView, context: Context) {
        view.tools = tools
        view.onToolBegin = onToolBegin
        view.onEraseEnd = onEraseEnd
        view.onPencilShortcut = onPencilShortcut
    }
}
