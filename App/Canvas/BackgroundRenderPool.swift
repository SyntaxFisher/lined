import CoreGraphics
import Foundation
import LinedLayout
import LinedRendering

/// Rasterizes page backgrounds off the main thread, a few at a time.
nonisolated final class BackgroundRenderPool: Sendable {
    private let queue: OperationQueue

    init(concurrentRenders: Int = 3) {
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = concurrentRenders
        queue.qualityOfService = .userInitiated
    }

    /// Returns `nil` when the calling task is cancelled before rendering has started.
    func image(of renderer: any PageBackgroundRenderer, pageSize: CGSize, request: RasterRequest) async -> CGImage? {
        let operation = RasterOperation(renderer: renderer, pageSize: pageSize, request: request)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                operation.completionBlock = { continuation.resume(returning: operation.image) }
                queue.addOperation(operation)
            }
        } onCancel: {
            operation.cancel()
        }
    }
}

/// `image` is written by `main()` and read by the completion block, which runs after `main()` has returned.
private nonisolated final class RasterOperation: Operation, @unchecked Sendable {
    private let renderer: any PageBackgroundRenderer
    private let pageSize: CGSize
    private let request: RasterRequest
    private(set) var image: CGImage?

    init(renderer: any PageBackgroundRenderer, pageSize: CGSize, request: RasterRequest) {
        self.renderer = renderer
        self.pageSize = pageSize
        self.request = request
    }

    override func main() {
        guard !isCancelled else { return }
        image = PageRasterizer.image(of: renderer, pageSize: pageSize, region: request.region, scale: request.scale)
    }
}
