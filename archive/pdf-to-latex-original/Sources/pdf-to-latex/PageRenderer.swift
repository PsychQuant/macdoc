import CoreGraphics
import Foundation
import PDFKit

struct RenderedPage {
    var pageNumber: Int
    var imagePath: String
}

enum PageRendererError: LocalizedError {
    case openFailed(URL)
    case pageUnavailable(Int)
    case bitmapCreationFailed(Int)
    case imageCreationFailed(Int)

    var errorDescription: String? {
        switch self {
        case .openFailed(let url):
            return "無法開啟 PDF: \(url.path)"
        case .pageUnavailable(let index):
            return "無法渲染第 \(index + 1) 頁，頁面不存在。"
        case .bitmapCreationFailed(let page):
            return "無法建立第 \(page) 頁的點陣畫布。"
        case .imageCreationFailed(let page):
            return "無法建立第 \(page) 頁的影像。"
        }
    }
}

struct PageRenderer {
    func renderPages(
        pdfAt url: URL,
        outputDirectory: URL,
        dpi: Double,
        firstPage: Int?,
        lastPage: Int?
    ) throws -> [RenderedPage] {
        guard let document = PDFDocument(url: url) else {
            throw PageRendererError.openFailed(url)
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let first = max((firstPage ?? 1), 1)
        let last = min((lastPage ?? document.pageCount), document.pageCount)
        guard first <= last else {
            return []
        }

        var renderedPages: [RenderedPage] = []
        for index in (first - 1)..<last {
            guard let page = document.page(at: index) else {
                throw PageRendererError.pageUnavailable(index)
            }

            let outputURL = outputDirectory.appendingPathComponent(String(format: "page-%04d.png", index + 1))
            try render(page: page, pageNumber: index + 1, outputURL: outputURL, dpi: dpi)
            renderedPages.append(RenderedPage(pageNumber: index + 1, imagePath: outputURL.path))
        }

        return renderedPages
    }

    private func render(page: PDFPage, pageNumber: Int, outputURL: URL, dpi: Double) throws {
        let bounds = page.bounds(for: .mediaBox)
        let scale = dpi / 72.0
        let pixelWidth = max(Int((bounds.width * scale).rounded(.up)), 1)
        let pixelHeight = max(Int((bounds.height * scale).rounded(.up)), 1)

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PageRendererError.bitmapCreationFailed(pageNumber)
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)

        guard let image = context.makeImage() else {
            throw PageRendererError.imageCreationFailed(pageNumber)
        }

        try CGImageWriter.writePNG(image, to: outputURL)
    }
}
