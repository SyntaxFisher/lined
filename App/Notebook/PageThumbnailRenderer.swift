import LinedLayout
import LinedRendering
import PencilKit
import UIKit

/// Renders a small picture of a page: its background with the ink on top.
nonisolated enum PageThumbnailRenderer {
    /// - Parameter maxPixelLength: The length of the image's longer side in pixels.
    @concurrent
    static func image(
        pageSize: CGSize,
        background: any PageBackgroundRenderer,
        drawing: PKDrawing,
        maxPixelLength: CGFloat
    ) async -> CGImage? {
        let scale = maxPixelLength / max(pageSize.width, pageSize.height)
        let region = PixelGrid.snapOutward(CGRect(origin: .zero, size: pageSize), pixelsPerPoint: scale)
        guard let paper = PageRasterizer.image(of: background, pageSize: pageSize, region: region, scale: scale) else {
            return nil
        }
        guard !drawing.strokes.isEmpty else { return paper }

        // Ink adapts to the current appearance; paper is always light.
        var ink: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = drawing.image(from: region, scale: scale)
        }
        let canvas = CGRect(x: 0, y: 0, width: paper.width, height: paper.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(bounds: canvas, format: format).image { _ in
            UIImage(cgImage: paper).draw(in: canvas)
            ink?.draw(in: canvas)
        }.cgImage
    }
}
