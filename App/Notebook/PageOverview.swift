import LinedModel
import SwiftUI

/// All pages of a notebook as thumbnails, for jumping to a page, reordering and removing pages and
/// adding pages at the end.
struct PageOverview: View {
    let session: NotebookSession

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 24)]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(session.pages) { page in
                            let index = session.document.index(of: page.id) ?? 0
                            Button {
                                session.showPage(page.id)
                                dismiss()
                            } label: {
                                PageThumbnailCell(
                                    session: session,
                                    page: page,
                                    number: index + 1,
                                    isCurrent: index == session.currentPageIndex
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete Page", systemImage: "trash", role: .destructive) {
                                    Task { await session.deletePage(page.id) }
                                }
                                .disabled(session.pages.count == 1)
                            }
                            .id(page.id)
                        }
                        .reorderable()
                        AddPageMenu(session: session, placement: .atEnd) {
                            NewPageCell(pageSize: session.pageBefore(.atEnd).successor().size)
                        }
                        .buttonStyle(.plain)
                        .id(Self.newPageID)
                    }
                    .padding(24)
                    .reorderContainer(for: Page.self) { difference in
                        let successor: Page.ID? = switch difference.destination.position {
                        case .before(let pageID): pageID
                        case .end: nil
                        }
                        Task { await session.movePages(difference.sources, before: successor) }
                    }
                }
                .onAppear {
                    proxy.scrollTo(session.currentPage.id, anchor: .center)
                }
                .onChange(of: session.pages.count) {
                    withAnimation { proxy.scrollTo(Self.newPageID, anchor: .bottom) }
                }
            }
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension PageOverview {
    static let newPageID = "new-page"
}

/// An outline of the page that would come next, in its size, offering to add it.
private struct NewPageCell: View {
    let pageSize: PageSize

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: PagePicture.cornerRadius * 2)
                .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                .overlay {
                    Image(systemName: "plus")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.tint)
                }
                .aspectRatio(pageSize.width / pageSize.height, contentMode: .fit)
                .frame(height: 190)
            // Keeps the outline level with the pages, which carry their number below.
            Text(verbatim: " ")
                .font(.footnote)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Add Page")
        .accessibilityAddTraits(.isButton)
    }
}

private struct PageThumbnailCell: View {
    let session: NotebookSession
    let page: Page
    let number: Int
    let isCurrent: Bool

    @State private var thumbnail: CGImage?

    var body: some View {
        VStack(spacing: 8) {
            PagePicture(image: thumbnail, aspectRatio: page.size.width / page.size.height)
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: PagePicture.cornerRadius)
                            .strokeBorder(.tint, lineWidth: 3)
                    }
                }
                .frame(height: 190)
            Text("\(number)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(number)")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .task(id: session.inkRevisions[page.id]) {
            thumbnail = await session.thumbnail(for: page)
        }
    }
}
