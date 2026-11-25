import Foundation
import LinedModel
import LinedRendering
import LinedStorage

/// Turns errors into sentences for the person using the app.
nonisolated enum ErrorMessage {
    static func text(for error: any Error) -> String {
        switch error {
        case PDFSourceError.passwordProtected:
            "This PDF is password-protected. Remove the password and import it again."
        case PDFSourceError.unreadable:
            "This file is not a readable PDF."
        case PDFSourceError.noPages:
            "This PDF has no pages."
        case LibraryError.emptyName:
            "A name can't be empty."
        case LibraryError.folderCannotContainItself:
            "A folder can't be moved into itself."
        case LibraryError.folderNotFound, LibraryError.notebookNotFound:
            "This item no longer exists."
        case StorageError.unsupportedFormatVersion:
            "This was saved by a newer version of Lined. Update the app to open it."
        case StorageError.corruptFile:
            "The file is damaged and can't be read."
        default:
            error.localizedDescription
        }
    }
}
