import LinedModel
import SwiftUI

/// Picks the folder an item moves to from the whole folder tree.
struct MoveSheet: View {
    let item: LibraryEntry

    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                destination(nil, name: "Library", symbol: "books.vertical", depth: 0)
                ForEach(library.library.folderHierarchy()) { node in
                    destination(node.folder.id, name: node.folder.name, symbol: "folder", depth: node.depth + 1)
                }
            }
            .navigationTitle("Move “\(item.name)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func destination(_ folderID: Folder.ID?, name: String, symbol: String, depth: Int) -> some View {
        let isCurrentLocation = item.parentID == folderID
        return Button {
            library.perform { try library.move(item.id, to: folderID) }
            dismiss()
        } label: {
            HStack {
                Label(name, systemImage: symbol)
                    .padding(.leading, CGFloat(depth) * 22)
                Spacer()
                if isCurrentLocation {
                    Text("Current Location")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isCurrentLocation || !library.library.canMove(item.id, to: folderID))
    }
}
