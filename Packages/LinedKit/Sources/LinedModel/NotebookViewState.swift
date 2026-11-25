import Foundation

/// Where the reader left a notebook. Kept apart from the document because viewing is not editing.
public struct NotebookViewState: Equatable, Codable, Sendable {
    public var lastViewedPageID: Page.ID?

    public init(lastViewedPageID: Page.ID? = nil) {
        self.lastViewedPageID = lastViewedPageID
    }
}
