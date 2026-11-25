import CoreGraphics

public enum PageRasterizer {
    /// Renders `region` of a page, given in page points, onto white paper at `scale` pixels per point.
    ///
    /// The image holds exactly the pixels of the region, so a region aligned to the pixel grid of `scale`
    /// maps one to one onto the screen.
    public static func image(
        of renderer: any PageBackgroundRenderer,
        pageSize: CGSize,
        region: CGRect,
        scale: CGFloat
    ) -> CGImage? {
        let pixelWidth = Int((region.width * scale).rounded())
        let pixelHeight = Int((region.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: opaqueBitmapInfo
              )
        else { return nil }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        // Bitmap space has its origin at the bottom-left corner; page space at the top-left.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -region.minX, y: -region.minY)
        context.clip(to: CGRect(origin: .zero, size: pageSize))
        renderer.draw(in: context, pageSize: pageSize)
        return context.makeImage()
    }

    private static let opaqueBitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
}
