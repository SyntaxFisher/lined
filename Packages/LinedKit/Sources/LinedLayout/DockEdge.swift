import CoreGraphics

/// The edge of the canvas that a floating tool bar rests at.
public enum DockEdge: String, Codable, CaseIterable, Sendable {
    case top
    case bottom
    case leading
    case trailing

    /// Whether a bar at this edge lays its tools out in a row.
    public var isHorizontal: Bool {
        self == .top || self == .bottom
    }

    /// The edge closest to a point, for docking a bar where it was dropped.
    ///
    /// - Parameter point: A point in a container of the given size, with `x` measured from the leading edge.
    public static func nearest(to point: CGPoint, in size: CGSize) -> DockEdge {
        let distances: [(edge: DockEdge, distance: CGFloat)] = [
            (.bottom, size.height - point.y),
            (.top, point.y),
            (.leading, point.x),
            (.trailing, size.width - point.x),
        ]
        return distances.min { $0.distance < $1.distance }!.edge
    }
}
