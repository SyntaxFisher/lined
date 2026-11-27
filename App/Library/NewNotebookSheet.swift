import LinedModel
import LinedRendering
import SwiftUI

/// Sets up a paper notebook: title, ruling and orientation. Notebooks are A4.
struct NewNotebookSheet: View {
    let folderID: Folder.ID?
    /// Called with the new notebook just before the sheet closes.
    let onCreate: (Notebook) -> Void

    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Preference.lastPaperTemplate) private var template = PaperTemplate.lined
    @State private var title = ""
    @State private var orientation = PageOrientation.portrait
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Untitled Notebook", text: $title)
                }
                Section("Paper") {
                    PaperTemplatePicker(selection: $template)
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16))
                    Picker("Orientation", selection: $orientation) {
                        Text("Portrait").tag(PageOrientation.portrait)
                        Text("Landscape").tag(PageOrientation.landscape)
                    }
                }
            }
            .pickerStyle(.segmented)
            .navigationTitle("New Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(isCreating)
                }
            }
        }
    }

    private func create() {
        isCreating = true
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let notebook = try await library.createNotebook(
                    titled: title.isEmpty ? String(localized: "Untitled Notebook") : title,
                    template: template,
                    pageSize: .a4(orientation),
                    in: folderID
                )
                onCreate(notebook)
                dismiss()
            } catch {
                isCreating = false
                library.failureMessage = ErrorMessage.text(for: error)
            }
        }
    }
}

private struct PaperTemplatePicker: View {
    @Binding var selection: PaperTemplate

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(PaperTemplate.allCases, id: \.self) { template in
                Button {
                    selection = template
                } label: {
                    VStack(spacing: 8) {
                        PagePicture(image: Self.previews[template], aspectRatio: 0.75)
                            .overlay {
                                if template == selection {
                                    RoundedRectangle(cornerRadius: PagePicture.cornerRadius)
                                        .strokeBorder(.tint, lineWidth: 3)
                                }
                            }
                        Text(template.displayName)
                            .font(.footnote)
                            .foregroundStyle(template == selection ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(template == selection ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The top-left corner of each paper at reading size, drawn by the renderer the pages use.
    private static let previews: [PaperTemplate: CGImage] = {
        let pageSize = PageSize.a4(.portrait).cgSize
        let corner = CGRect(x: 0, y: 0, width: 150, height: 200)
        return Dictionary(uniqueKeysWithValues: PaperTemplate.allCases.compactMap { template in
            PageRasterizer
                .image(of: PaperBackgroundRenderer(template: template), pageSize: pageSize, region: corner, scale: 3)
                .map { (template, $0) }
        })
    }()
}
