import SwiftUI

/// The pages of an open notebook: scrolling, zooming and handwriting.
struct NotebookCanvas: UIViewRepresentable {
    let session: NotebookSession
    let allowsFingerDrawing: Bool
    let isToolPickerVisible: Bool

    func makeUIView(context: Context) -> PagedCanvasView {
        let view = PagedCanvasView()
        view.delegate = session
        session.attach(view)
        return view
    }

    func updateUIView(_ view: PagedCanvasView, context: Context) {
        view.allowsFingerDrawing = allowsFingerDrawing
        view.isToolPickerVisible = isToolPickerVisible
    }
}
