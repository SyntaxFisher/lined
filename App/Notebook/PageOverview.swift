import LinedModel
import SwiftUI

/// All pages of a notebook as thumbnails, for jumping to a page and removing pages.
struct PageOverview: View {
    let session: NotebookSession

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 24)]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(Array(session.pages.enumerated()), id: \.element.id) { index, page in
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
                    }
                    .padding(24)
                }
                .onAppear {
                    proxy.scrollTo(session.currentPage.id, anchor: .center)
                }
            }
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AddPageMenu(session: session)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
