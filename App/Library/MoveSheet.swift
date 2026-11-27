import LinedModel
import SwiftUI

/// Items the user wants to move, waiting for a destination.
struct MoveRequest: Identifiable {
    let id = UUID()
    let items: [LibraryEntry]
}

/// Picks the folder items move to from the whole folder tree.
struct MoveSheet: View {
    let request: MoveRequest
    var onMove: () -> Void = {}

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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var title: String {
        if let item = request.items.first, request.items.count == 1 {
            String(localized: "Move “\(item.name)”")
        } else {
            String(localized: "Move \(request.items.count) Items")
        }
    }

    private func destination(_ folderID: Folder.ID?, name: String, symbol: String, depth: Int) -> some View {
        let isCurrentLocation = request.items.allSatisfy { $0.parentID == folderID }
        return Button {
            library.perform { try library.move(request.items.map(\.id), to: folderID) }
            onMove()
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
        .disabled(!library.library.canMove(request.items.map(\.id), to: folderID))
    }
}
