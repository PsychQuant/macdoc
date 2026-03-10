import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CGImageWriterError: LocalizedError {
    case cannotCreateDestination(URL)
    case finalizeFailed(URL)

    var errorDescription: String? {
        switch self {
        case .cannotCreateDestination(let url):
            return "無法建立圖片輸出: \(url.path)"
        case .finalizeFailed(let url):
            return "無法完成圖片輸出: \(url.path)"
        }
    }
}

enum CGImageWriter {
    static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CGImageWriterError.cannotCreateDestination(url)
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CGImageWriterError.finalizeFailed(url)
        }
    }
}
