import CoreGraphics

/// The desk the pages lie on: everything in view that is not a page.
public enum Desk {
    /// The rectangles that fill `area` around the pages.
    ///
    /// - Parameter pageFrames: The pages that reach into `area`, from top to bottom. Pages lie one
    ///   below the other and do not overlap.
    public static func rects(around pageFrames: [CGRect], in area: CGRect) -> [CGRect] {
        var rects: [CGRect] = []
        var top = area.minY
        for frame in pageFrames {
            let page = frame.intersection(area)
            guard !page.isEmpty else { continue }
            if page.minY > top {
                rects.append(CGRect(x: area.minX, y: top, width: area.width, height: page.minY - top))
            }
            if page.minX > area.minX {
                rects.append(CGRect(x: area.minX, y: page.minY, width: page.minX - area.minX, height: page.height))
            }
            if page.maxX < area.maxX {
                rects.append(CGRect(x: page.maxX, y: page.minY, width: area.maxX - page.maxX, height: page.height))
            }
            top = page.maxY
        }
        if top < area.maxY {
            rects.append(CGRect(x: area.minX, y: top, width: area.width, height: area.maxY - top))
        }
        return rects
    }
}
