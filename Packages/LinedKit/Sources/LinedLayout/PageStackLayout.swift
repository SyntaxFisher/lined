import CoreGraphics

/// The vertical stack of a notebook's pages in document space: page points, origin at the top-left of the stack.
public struct PageStackLayout: Equatable, Sendable {
    public struct Metrics: Equatable, Sendable {
        /// Space around the stack.
        public var margin: CGFloat
        /// Space between two pages.
        public var spacing: CGFloat

        public init(margin: CGFloat, spacing: CGFloat) {
            self.margin = margin
            self.spacing = spacing
        }

        public static let standard = Metrics(margin: 10, spacing: 10)
    }

    public let contentSize: CGSize
    private let frames: [CGRect]

    public init(pageSizes: [CGSize], metrics: Metrics = .standard) {
        let contentWidth = (pageSizes.map(\.width).max() ?? 0) + metrics.margin * 2
        var y = metrics.margin
        frames = pageSizes.map { size in
            defer { y += size.height + metrics.spacing }
            return CGRect(x: (contentWidth - size.width) / 2, y: y, width: size.width, height: size.height)
        }
        contentSize = CGSize(width: contentWidth, height: frames.last.map { $0.maxY + metrics.margin } ?? 0)
    }

    public var pageCount: Int { frames.count }

    public func frame(ofPageAt index: Int) -> CGRect { frames[index] }

    /// The pages that share a vertical span with `rect`.
    public func pageIndices(intersecting rect: CGRect) -> Range<Int> {
        let lower = firstIndex { $0.maxY > rect.minY }
        let upper = firstIndex { $0.minY >= rect.maxY }
        return lower..<max(lower, upper)
    }

    /// The page at height `y`, or the closest one when `y` falls into a gap. `nil` for an empty stack.
    public func pageIndex(nearestTo y: CGFloat) -> Int? {
        guard let last = frames.indices.last else { return nil }
        let index = firstIndex { $0.maxY >= y }
        guard index <= last else { return last }
        guard index > 0, y < frames[index].minY else { return index }
        let distanceToPrevious = y - frames[index - 1].maxY
        let distanceToNext = frames[index].minY - y
        return distanceToPrevious <= distanceToNext ? index - 1 : index
    }

    /// The zoom at which the stack is exactly as wide as the viewport.
    public func zoom(fittingWidth viewportWidth: CGFloat) -> CGFloat {
        contentSize.width > 0 ? viewportWidth / contentSize.width : 1
    }

    /// Frames are sorted by position, so every predicate that is false for a prefix and true for the rest
    /// can be answered by binary search.
    private func firstIndex(where predicate: (CGRect) -> Bool) -> Int {
        var low = 0
        var high = frames.count
        while low < high {
            let middle = (low + high) / 2
            if predicate(frames[middle]) {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }
}

public enum PixelGrid {
    public static func snap(_ value: CGFloat, pixelsPerPoint: CGFloat) -> CGFloat {
        (value * pixelsPerPoint).rounded() / pixelsPerPoint
    }

    public static func snap(_ point: CGPoint, pixelsPerPoint: CGFloat) -> CGPoint {
        CGPoint(x: snap(point.x, pixelsPerPoint: pixelsPerPoint), y: snap(point.y, pixelsPerPoint: pixelsPerPoint))
    }

    /// The smallest rectangle on the pixel grid that contains `rect`.
    public static func snapOutward(_ rect: CGRect, pixelsPerPoint: CGFloat) -> CGRect {
        // Values a rounding error away from a pixel boundary count as on it.
        let tolerance: CGFloat = 1e-6
        let minX = (rect.minX * pixelsPerPoint + tolerance).rounded(.down)
        let minY = (rect.minY * pixelsPerPoint + tolerance).rounded(.down)
        let maxX = (rect.maxX * pixelsPerPoint - tolerance).rounded(.up)
        let maxY = (rect.maxY * pixelsPerPoint - tolerance).rounded(.up)
        return CGRect(
            x: minX / pixelsPerPoint,
            y: minY / pixelsPerPoint,
            width: (maxX - minX) / pixelsPerPoint,
            height: (maxY - minY) / pixelsPerPoint
        )
    }
}
