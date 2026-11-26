import PencilKit

extension PKStroke {
    /// A straight pen stroke with the point attributes a finger leaves, which the canvas needs to draw it.
    static func line(from start: CGPoint, to end: CGPoint, width: CGFloat = 2.4) -> PKStroke {
        let steps = 40
        let points = (0...steps).map { step in
            let fraction = CGFloat(step) / CGFloat(steps)
            return PKStrokePoint(
                location: CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction),
                timeOffset: TimeInterval(fraction) * 0.3,
                size: CGSize(width: width, height: width),
                opacity: 1,
                force: 0,
                azimuth: 0,
                altitude: .pi / 2,
                secondaryScale: 0.32
            )
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }
}

extension PKDrawing {
    /// How many pixels of `rect` the ink covers, rendered at one pixel per point.
    func inkedPixels(in rect: CGRect) -> Int {
        let image = self.image(from: rect, scale: 1)
        guard let cgImage = image.cgImage,
              let context = CGContext(
                data: nil, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8,
                bytesPerRow: cgImage.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard let data = context.data else { return 0 }
        let bytes = data.bindMemory(to: UInt8.self, capacity: cgImage.width * cgImage.height * 4)
        return (0..<(cgImage.width * cgImage.height)).count { bytes[$0 * 4 + 3] > 128 }
    }
}
