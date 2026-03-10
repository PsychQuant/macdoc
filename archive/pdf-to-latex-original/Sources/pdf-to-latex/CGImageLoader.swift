import CoreGraphics
import Foundation
import ImageIO

enum CGImageLoaderError: LocalizedError {
    case cannotOpen(URL)
    case cannotDecode(URL)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let url):
            return "無法開啟圖片檔: \(url.path)"
        case .cannotDecode(let url):
            return "無法解碼圖片檔: \(url.path)"
        }
    }
}

enum CGImageLoader {
    static func load(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw CGImageLoaderError.cannotOpen(url)
        }

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CGImageLoaderError.cannotDecode(url)
        }

        return image
    }
}
