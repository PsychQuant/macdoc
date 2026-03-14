import Foundation
import AppKit
import CoreGraphics
import OOXMLSwift
@testable import PDFToDOCXSwift

#if canImport(XCTest)
import XCTest

final class PDFToDOCXConverterTests: XCTestCase {
    private let converter = PDFToDOCXConverter()
    private var cleanupURLs: [URL] = []

    override func tearDown() {
        for url in cleanupURLs {
            try? FileManager.default.removeItem(at: url)
        }
        cleanupURLs.removeAll()
        super.tearDown()
    }

    func testConvertToStringStreamsWordDocumentXML() throws {
        let pdfURL = try makePDF(
            named: "basic.pdf",
            metadata: [.title: "Sample Title"],
            pages: [["Sample Title", "", "Hello world from PDF"]]
        )

        let xml = try converter.convertToString(input: pdfURL)

        XCTAssertTrue(xml.contains("<w:document"), "Got: \(xml)")
        XCTAssertTrue(xml.contains("Sample Title"), "Got: \(xml)")
        XCTAssertTrue(xml.contains("Hello world from PDF"), "Got: \(xml)")
    }

    func testConvertToFilePreservesMetadataAndHeading() throws {
        let pdfURL = try makePDF(
            named: "metadata.pdf",
            metadata: [
                .title: "Research Note",
                .author: "Che Cheng",
                .subject: "PDF Import",
                .keywords: ["macdoc", "pdf", "docx"],
            ],
            pages: [["Research Note", "", "Structured body text"]]
        )
        let outputURL = pdfURL.deletingPathExtension().appendingPathExtension("docx")

        try converter.convertToFile(input: pdfURL, output: outputURL)
        let document = try DocxReader.read(from: outputURL)
        let paragraphs = document.getParagraphs()

        XCTAssertEqual(document.properties.title, "Research Note")
        XCTAssertEqual(document.properties.creator, "Che Cheng")
        XCTAssertEqual(document.properties.subject, "PDF Import")
        XCTAssertEqual(document.properties.keywords, "macdoc, pdf, docx")
        XCTAssertEqual(paragraphs.first?.properties.style, "Heading1")
        XCTAssertEqual(paragraphs.dropFirst().first?.getText(), "Structured body text")
    }

    func testMultiplePagesProducePageBreakParagraph() throws {
        let pdfURL = try makePDF(
            named: "pages.pdf",
            pages: [
                ["Page One", "", "alpha"],
                ["Page Two", "", "beta"],
            ]
        )
        let outputURL = pdfURL.deletingPathExtension().appendingPathExtension("docx")

        try converter.convertToFile(input: pdfURL, output: outputURL)
        let document = try DocxReader.read(from: outputURL)

        XCTAssertTrue(document.getParagraphs().contains(where: { $0.properties.pageBreakBefore }))
    }

    func testTableLikeContentBecomesWordTable() throws {
        let pdfURL = try makePDF(
            named: "table.pdf",
            pages: [["Header A | Header B", "Value 1 | Value 2"]]
        )
        let outputURL = pdfURL.deletingPathExtension().appendingPathExtension("docx")

        try converter.convertToFile(input: pdfURL, output: outputURL)
        let document = try DocxReader.read(from: outputURL)
        let tables = document.getTables()

        XCTAssertEqual(tables.count, 1)
        XCTAssertEqual(tables.first?.rows.first?.cells.first?.getText(), "Header A")
        XCTAssertEqual(tables.first?.rows.last?.cells.last?.getText(), "Value 2")
    }

    func testBulletLinesBecomeNumberedParagraphs() throws {
        let pdfURL = try makePDF(
            named: "list.pdf",
            pages: [["• First item", "• Second item"]]
        )
        let outputURL = pdfURL.deletingPathExtension().appendingPathExtension("docx")

        try converter.convertToFile(input: pdfURL, output: outputURL)
        let document = try DocxReader.read(from: outputURL)
        let paragraphs = document.getParagraphs()

        XCTAssertEqual(paragraphs.count, 2)
        XCTAssertEqual(paragraphs.first?.properties.numbering?.level, 0)
        XCTAssertEqual(paragraphs.first?.getText(), "First item")
        XCTAssertEqual(paragraphs.last?.getText(), "Second item")
    }

    private func makePDF(
        named name: String,
        metadata: PDFMetadata = [:],
        pages: [[String]]
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cleanupURLs.append(directory)

        let url = directory.appendingPathComponent(name)
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let auxiliaryInfo = metadata.isEmpty ? nil : metadata.toCoreGraphicsDictionary()

        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(
                consumer: consumer,
                mediaBox: &mediaBox,
                auxiliaryInfo as CFDictionary?
              ) else {
            XCTFail("Failed to create PDF context")
            return url
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18)
        ]

        for lines in pages {
            context.beginPDFPage(nil)
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext

            var y: CGFloat = 720
            for line in lines {
                NSString(string: line).draw(at: CGPoint(x: 72, y: y), withAttributes: attributes)
                y -= 28
            }

            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }

        context.closePDF()
        return url
    }
}

private enum PDFMetadataKey {
    case title
    case author
    case subject
    case keywords
}

private typealias PDFMetadata = [PDFMetadataKey: Any]

private extension Dictionary where Key == PDFMetadataKey, Value == Any {
    func toCoreGraphicsDictionary() -> [CFString: Any] {
        var dictionary: [CFString: Any] = [:]

        if let title = self[.title] as? String {
            dictionary[kCGPDFContextTitle] = title
        }
        if let author = self[.author] as? String {
            dictionary[kCGPDFContextAuthor] = author
        }
        if let subject = self[.subject] as? String {
            dictionary[kCGPDFContextSubject] = subject
        }
        if let keywords = self[.keywords] as? [String] {
            dictionary[kCGPDFContextKeywords] = keywords
        }

        return dictionary
    }
}
#endif
