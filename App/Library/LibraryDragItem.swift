import CoreTransferable
import Foundation
import LinedModel
import UniformTypeIdentifiers

/// A folder or notebook dragged within the library. It only names the item, so it is useless outside the app.
struct LibraryDragItem: Identifiable, Codable, Transferable {
    let id: LibraryEntry.ID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .libraryItem)
    }
}

extension UTType {
    /// Declared in the app's Info.plist under the bundle identifier, which differs between builds.
    nonisolated static let libraryItem = UTType(exportedAs: "\(Bundle.main.bundleIdentifier ?? "").library-item")
}
