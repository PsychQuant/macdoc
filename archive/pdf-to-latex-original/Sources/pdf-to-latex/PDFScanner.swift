import Foundation
import PDFKit

struct PDFPageSnapshot {
    var number: Int
    var width: Double
    var height: Double
    var rotation: Int
}

enum PDFScannerError: LocalizedError {
    case openFailed(URL)
    case pageUnavailable(Int)

    var errorDescription: String? {
        switch self {
        case .openFailed(let url):
            return "無法開啟 PDF: \(url.path)"
        case .pageUnavailable(let index):
            return "無法讀取 PDF 第 \(index + 1) 頁。"
        }
    }
}

struct PDFScanner {
    func scan(pdfAt url: URL) throws -> [PDFPageSnapshot] {
        guard let document = PDFDocument(url: url) else {
            throw PDFScannerError.openFailed(url)
        }

        return try (0..<document.pageCount).map { index in
            guard let page = document.page(at: index) else {
                throw PDFScannerError.pageUnavailable(index)
            }

            let bounds = page.bounds(for: .mediaBox)
            return PDFPageSnapshot(
                number: index + 1,
                width: Double(bounds.width),
                height: Double(bounds.height),
                rotation: Int(page.rotation)
            )
        }
    }
}
