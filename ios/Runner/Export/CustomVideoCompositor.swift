import Foundation
import AVFoundation
import CoreImage
import UIKit

class CustomVideoCompositor: NSObject, AVVideoCompositing {

    var sourcePixelBufferAttributes: [String : Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    var requiredPixelBufferAttributesForRenderContext: [String : Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        guard let pixelBuffer = asyncVideoCompositionRequest.sourceFrame(byTrackID: asyncVideoCompositionRequest.sourceTrackIDs[0].int32Value) else {
            asyncVideoCompositionRequest.finish(with: NSError(domain: "Compositor", code: -1, userInfo: nil))
            return
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let outputPixelBuffer = asyncVideoCompositionRequest.renderContext.newPixelBuffer()

        if let outputPixelBuffer = outputPixelBuffer {
            let context = CIContext()
            context.render(ciImage, to: outputPixelBuffer)
            asyncVideoCompositionRequest.finish(withComposedVideoFrame: outputPixelBuffer)
        } else {
            asyncVideoCompositionRequest.finish(withComposedVideoFrame: pixelBuffer)
        }
    }
}
