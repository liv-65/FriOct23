import UIKit
import Vision
import CoreImage

/// 用 Vision 的主体识别（和相册"长按抠图"同一套能力）把衣服抠出来，全程在本机完成
enum BackgroundRemover {
    private static let ciContext = CIContext()

    static func cutout(_ image: UIImage) throws -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
        let buffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: true
        )
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let output = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: output)
    }
}
