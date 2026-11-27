import CoreGraphics
import LinedLayout

/// Converts between the ink of single pages and the ink that a canvas shows for the whole page stack.
///
/// Pages store their ink in page points. The canvas draws in document points, where each page lies at
/// its frame in the stack, magnified by the layout's scale. A stroke belongs to the page it starts on, or to the nearest page when it
/// starts between pages. Ink ends at the edge of its page: a stroke drawn across several pages is
/// split into one stroke on each of them.
///
/// Pages are addressed by their index in the layout.
public enum DocumentInk {
    /// Places the ink of pages, given in page points, at the pages' positions in the stack.
    public static func strokes<Stroke: InkStroke>(joining pageInk: [Int: [Stroke]], layout: PageStackLayout) -> [Stroke] {
        pageInk.sorted { $0.key < $1.key }.flatMap { index, ink in
            index < layout.pageCount ? placed(ink, onPageAt: index, layout: layout) : []
        }
    }

    /// Sorts document ink by page, leaving the strokes where they are. Strokes keep their order within a page.
    public static func strokesByPage<Stroke: InkStroke>(in strokes: [Stroke], layout: PageStackLayout) -> [Int: [Stroke]] {
        var strokesByPage: [Int: [Stroke]] = [:]
        for stroke in strokes {
            guard let index = pageIndex(of: stroke, layout: layout) else { continue }
            strokesByPage[index, default: []].append(stroke)
        }
        return strokesByPage
    }

    /// Takes document ink apart into the ink of the pages that have any, in page points.
    public static func pageInk<Stroke: InkStroke>(in strokes: [Stroke], layout: PageStackLayout) -> [Int: [Stroke]] {
        var pageInk = strokesByPage(in: strokes, layout: layout)
        for index in pageInk.keys {
            pageInk[index] = lifted(pageInk[index]!, fromPageAt: index, layout: layout)
        }
        return pageInk
    }

    /// Converts strokes that lie on a page in the stack to page points.
    public static func lifted<Stroke: InkStroke>(_ strokes: [Stroke], fromPageAt index: Int, layout: PageStackLayout) -> [Stroke] {
        let toPage = layout.transform(ofPageAt: index).inverted()
        return strokes.map { $0.applying(toPage) }
    }

    /// Adds the ink of a page, given in page points, beneath the ink that is already there.
    ///
    /// Strokes drawn on a page while its stored ink was still being read are younger than that ink
    /// and stay on top of it.
    public static func strokes<Stroke: InkStroke>(
        _ strokes: [Stroke],
        adding ink: [Stroke],
        beneathPageAt index: Int,
        layout: PageStackLayout
    ) -> [Stroke] {
        placed(ink, onPageAt: index, layout: layout) + strokes
    }

    /// Drops the strokes of the given pages.
    public static func strokes<Stroke: InkStroke>(_ strokes: [Stroke], removingPagesAt indices: Set<Int>, layout: PageStackLayout) -> [Stroke] {
        strokes.filter { stroke in
            pageIndex(of: stroke, layout: layout).map { !indices.contains($0) } ?? true
        }
    }

    /// Exchanges the strokes of one page for the given ink in page points.
    public static func strokes<Stroke: InkStroke>(
        _ strokes: [Stroke],
        replacingPageAt index: Int,
        with ink: [Stroke],
        layout: PageStackLayout
    ) -> [Stroke] {
        self.strokes(strokes, removingPagesAt: [index], layout: layout) + placed(ink, onPageAt: index, layout: layout)
    }

    /// Carries the ink along when the page stack changes.
    ///
    /// - Parameter newIndices: Where each page of the old layout lies in the new one. The ink of pages
    ///   that are missing here is dropped.
    public static func strokes<Stroke: InkStroke>(
        _ strokes: [Stroke],
        movedFrom oldLayout: PageStackLayout,
        to newLayout: PageStackLayout,
        newIndices: [Int: Int]
    ) -> [Stroke] {
        strokes.compactMap { stroke in
            guard let oldIndex = pageIndex(of: stroke, layout: oldLayout), let newIndex = newIndices[oldIndex] else { return nil }
            let from = oldLayout.transform(ofPageAt: oldIndex)
            let to = newLayout.transform(ofPageAt: newIndex)
            return from == to ? stroke : stroke.applying(from.inverted().concatenating(to))
        }
    }

    /// Splits the strokes that run past the edge of their page into one stroke on each page they
    /// draw on. What a stroke draws beside the pages is dropped.
    ///
    /// - Returns: The strokes, each one on a single page, or `nil` when all of them lie on a single
    ///   page already. The parts of a stroke take its place, in the order of the pages.
    public static func strokesSplitAtPages<Stroke: InkStroke>(_ strokes: [Stroke], layout: PageStackLayout) -> [Stroke]? {
        var split: [Stroke] = []
        var isChanged = false
        for stroke in strokes {
            if let index = pageIndex(of: stroke, layout: layout), lies(stroke, inside: layout.frame(ofPageAt: index)) {
                split.append(stroke)
            } else {
                isChanged = true
                split += layout.pageIndices(intersecting: stroke.bounds).compactMap { stroke.clipped(to: layout.frame(ofPageAt: $0)) }
            }
        }
        return isChanged ? split : nil
    }

    /// Whether a stroke stays inside `rect`, give or take the rounding of moving it between pages and the stack.
    private static func lies(_ stroke: some InkStroke, inside rect: CGRect) -> Bool {
        rect.insetBy(dx: -0.01, dy: -0.01).contains(stroke.bounds)
    }

    /// The page a stroke belongs to, or `nil` when the stack is empty.
    public static func pageIndex(of stroke: some InkStroke, layout: PageStackLayout) -> Int? {
        layout.pageIndex(nearestTo: stroke.start.y)
    }

    private static func placed<Stroke: InkStroke>(_ ink: [Stroke], onPageAt index: Int, layout: PageStackLayout) -> [Stroke] {
        let toDocument = layout.transform(ofPageAt: index)
        return ink.map { $0.applying(toDocument) }
    }
}
