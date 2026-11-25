import CoreGraphics
import Foundation

/// The pixels of an image, addressed from the top-left corner.
struct Bitmap: Equatable {
    struct Color: Equatable {
        var red: UInt8
        var green: UInt8
        var blue: UInt8

        static let white = Color(red: 255, green: 255, blue: 255)
        static let red = Color(red: 255, green: 0, blue: 0)
        static let blue = Color(red: 0, green: 0, blue: 255)
    }

    let width: Int
    let height: Int
    private var bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    func color(x: Int, y: Int) -> Color {
        let offset = (y * width + x) * 4
        return Color(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2])
    }

    func cropped(x: Int, y: Int, width cropWidth: Int, height cropHeight: Int) -> [Color] {
        (y..<y + cropHeight).flatMap { row in (x..<x + cropWidth).map { color(x: $0, y: row) } }
    }

    var colors: [Color] { cropped(x: 0, y: 0, width: width, height: height) }
}

final class PDFFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "LinedRenderingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func url(_ name: String) -> URL {
        directory.appending(path: name, directoryHint: .notDirectory)
    }

    /// Page 1 is 400 x 600 with a red top-left quadrant, page 2 is 600 x 400 with a blue bottom-right quadrant.
    func writeTwoPageDocument(named name: String = "two-pages.pdf", password: String? = nil) -> URL {
        let url = url(name)
        let options = password.map { [kCGPDFContextUserPassword: $0, kCGPDFContextOwnerPassword: $0] as CFDictionary }
        let context = CGContext(url as CFURL, mediaBox: nil, options)!

        var portrait = CGRect(x: 0, y: 0, width: 400, height: 600)
        context.beginPage(mediaBox: &portrait)
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 300, width: 200, height: 300))
        context.endPage()

        var landscape = CGRect(x: 0, y: 0, width: 600, height: 400)
        context.beginPage(mediaBox: &landscape)
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 300, y: 0, width: 300, height: 200))
        context.endPage()

        context.closePDF()
        return url
    }
}
