import CoreGraphics

/// What the page logic needs to know about a stroke of ink, whatever draws it.
public protocol InkStroke {
    /// Where the stroke starts, in the coordinates of the drawing that holds it.
    var start: CGPoint { get }

    /// The same stroke at another place.
    func moved(by offset: CGVector) -> Self

    /// Feeds everything that makes up the stroke's appearance into the hasher.
    ///
    /// Positions go in through `InkFingerprint.combine(_:relativeTo:into:)`, so that a stroke gives
    /// the same value in page coordinates and, relative to its page's origin, in document coordinates.
    func fingerprint(into hasher: inout Hasher, relativeTo origin: CGPoint)
}

/// A value that changes whenever the strokes on a page change, for telling which pages were edited
/// without comparing or encoding their ink.
public struct InkFingerprint: Hashable, Sendable {
    private let value: Int

    /// - Parameter origin: The origin of the strokes' page in the coordinates the strokes are in.
    public init(of strokes: [some InkStroke], relativeTo origin: CGPoint = .zero) {
        var hasher = Hasher()
        hasher.combine(strokes.count)
        for stroke in strokes {
            stroke.fingerprint(into: &hasher, relativeTo: origin)
        }
        value = hasher.finalize()
    }

    /// Feeds a position into the hasher at a resolution far finer than anything visible, yet coarser
    /// than the rounding errors of moving between page and document coordinates.
    public static func combine(_ point: CGPoint, relativeTo origin: CGPoint, into hasher: inout Hasher) {
        hasher.combine(((point.x - origin.x) * 1024).rounded())
        hasher.combine(((point.y - origin.y) * 1024).rounded())
    }
}
