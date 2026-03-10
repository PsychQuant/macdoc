import CoreGraphics
import Foundation

enum BlockImageCropperError: LocalizedError {
    case invalidCrop(BoundingBox)
    case cropFailed(URL)
    var errorDescription: String? {
        switch self {
        case .invalidCrop(let bbox):
            return "block bbox 無效: \(bbox)"
        case .cropFailed(let url):
            return "無法從頁面圖片裁出 block: \(url.path)"
        }
    }
}

struct BlockImageCropper {
    func crop(
        pageImageURL: URL,
        pageWidth: Double,
        pageHeight: Double,
        bbox: BoundingBox,
        outputURL: URL
    ) throws {
        guard bbox.width > 0, bbox.height > 0 else {
            throw BlockImageCropperError.invalidCrop(bbox)
        }

        let pageImage = try CGImageLoader.load(from: pageImageURL)
        let scaleX = Double(pageImage.width) / pageWidth
        let scaleY = Double(pageImage.height) / pageHeight

        var rect = CGRect(
            x: floor(bbox.x * scaleX),
            y: floor((pageHeight - bbox.y - bbox.height) * scaleY),
            width: ceil(bbox.width * scaleX),
            height: ceil(bbox.height * scaleY)
        )
        rect = rect.intersection(CGRect(x: 0, y: 0, width: pageImage.width, height: pageImage.height))

        guard !rect.isNull, rect.width > 0, rect.height > 0, let cropped = pageImage.cropping(to: rect) else {
            throw BlockImageCropperError.cropFailed(pageImageURL)
        }
        try CGImageWriter.writePNG(cropped, to: outputURL)
    }
}
