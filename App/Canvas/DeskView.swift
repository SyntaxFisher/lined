import UIKit

/// Shows the desk around the pages above the ink, so that nothing written past a page's edge is seen.
///
/// The desk is made of plain rectangles. They stay small in number and close to the viewport, which
/// keeps them exact at every zoom.
final class DeskView: UIView {
    private var covers: [CALayer] = []
    private var rects: [CGRect] = []

    var deskColor: UIColor = .clear {
        didSet {
            covers.forEach { $0.backgroundColor = deskColor.cgColor }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// - Parameter rects: The parts of the desk in view, in the view's coordinates.
    func show(_ rects: [CGRect]) {
        guard rects != self.rects else { return }
        self.rects = rects
        while covers.count < rects.count {
            covers.append(makeCover())
        }
        for (index, cover) in covers.enumerated() {
            cover.isHidden = index >= rects.count
            if index < rects.count {
                cover.frame = rects[index]
            }
        }
    }

    private func makeCover() -> CALayer {
        let cover = CALayer()
        cover.backgroundColor = deskColor.cgColor
        cover.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull(), "backgroundColor": NSNull()]
        layer.addSublayer(cover)
        return cover
    }
}
