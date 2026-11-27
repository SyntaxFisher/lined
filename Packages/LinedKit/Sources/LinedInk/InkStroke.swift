import CoreGraphics

/// What the page logic needs to know about a stroke of ink, whatever draws it.
public protocol InkStroke {
    /// Where the stroke starts, in the coordinates of the drawing that holds it. For a stroke that
    /// was cut, where what is left of it starts.
    var start: CGPoint { get }

    /// The smallest rectangle that holds everything the stroke draws.
    var bounds: CGRect { get }

    /// The same stroke moved, and scaled along with its line, by `transform`.
    func applying(_ transform: CGAffineTransform) -> Self

    /// What the stroke draws inside `rect`, or `nil` when it draws nothing there.
    func clipped(to rect: CGRect) -> Self?

    /// Feeds everything that makes up the stroke's appearance on its page into the hasher, so that a
    /// stroke gives the same value in page points and in document points.
    ///
    /// - Parameter page: Converts page points to the coordinates the stroke is in. Positions go in
    ///   through `InkFingerprint.combine(_:into:)` after converting them to page points.
    func fingerprint(into hasher: inout Hasher, onPage page: CGAffineTransform)
}

/// A value that changes whenever the strokes on a page change, for telling which pages were edited
/// without comparing or encoding their ink.
public struct InkFingerprint: Hashable, Sendable {
    private var value: UInt64 = 0xcbf2_9ce4_8422_2325

    /// The fingerprint of a page without ink.
    public init() {}

    /// - Parameter page: Converts page points to the coordinates the strokes are in.
    public init(of strokes: [some InkStroke], onPage page: CGAffineTransform = .identity) {
        add(strokes, onPage: page)
    }

    /// Turns the fingerprint into that of its strokes followed by `strokes`, at the cost of the
    /// added strokes alone.
    public mutating func add(_ strokes: [some InkStroke], onPage page: CGAffineTransform = .identity) {
        for stroke in strokes {
            var hasher = Hasher()
            stroke.fingerprint(into: &hasher, onPage: page)
            value = (value &* 0x0000_0100_0000_01b3) ^ UInt64(truncatingIfNeeded: hasher.finalize())
        }
    }

    /// Feeds a position or size into the hasher at a resolution far finer than anything visible, yet
    /// coarser than the rounding errors of moving between page and document coordinates.
    public static func combine(_ point: CGPoint, into hasher: inout Hasher) {
        hasher.combine((point.x * 1024).rounded())
        hasher.combine((point.y * 1024).rounded())
    }
}
