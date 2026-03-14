import XCTest
import AppKit
import PDFKit
import DocConverterSwift
@testable import PDFToMDSwift

final class PDFConverterTests: XCTestCase {
    private let converter = PDFConverter()

    func testConvertsHeadingParagraphAndBulletList() throws {
        let pdf = try makePDF(
            named: "structure.pdf",
            pages: [[
                DrawBlock(text: "Quarterly Results", fontSize: 28, origin: CGPoint(x: 72, y: 700)),
                DrawBlock(
                    text: "Revenue increased year over year.\nMargin expansion continued.",
                    fontSize: 18,
                    origin: CGPoint(x: 72, y: 300)
                ),
                DrawBlock(text: "• Revenue\n• Margin", fontSize: 18, origin: CGPoint(x: 72, y: 140)),
            ]]
        )

        let markdown = try convert(pdf)

        XCTAssert(markdown.contains("# Quarterly Results"), "Got: \(markdown)")
        XCTAssert(markdown.contains("Revenue increased year over year. Margin expansion continued."), "Got: \(markdown)")
        XCTAssert(markdown.contains("- Revenue"), "Got: \(markdown)")
        XCTAssert(markdown.contains("- Margin"), "Got: \(markdown)")
    }

    func testConvertsOrderedListAndHardBreaks() throws {
        let pdf = try makePDF(
            named: "ordered-and-breaks.pdf",
            pages: [[
                DrawBlock(text: "Line one\nLine two", fontSize: 18, origin: CGPoint(x: 72, y: 560)),
                DrawBlock(text: "1. Collect data\n2. Review output", fontSize: 18, origin: CGPoint(x: 72, y: 380)),
            ]]
        )

        var options = ConversionOptions.default
        options.hardLineBreaks = true
        let markdown = try convert(pdf, options: options)

        XCTAssert(markdown.contains("Line one  \nLine two"), "Got: \(markdown)")
        XCTAssert(markdown.contains("1. Collect data"), "Got: \(markdown)")
        XCTAssert(markdown.contains("2. Review output"), "Got: \(markdown)")
    }

    func testInsertsPageBreakBetweenPages() throws {
        let pdf = try makePDF(
            named: "page-breaks.pdf",
            pages: [
                [DrawBlock(text: "Page one paragraph.", fontSize: 18, origin: CGPoint(x: 72, y: 640))],
                [DrawBlock(text: "Page two paragraph.", fontSize: 18, origin: CGPoint(x: 72, y: 640))],
            ]
        )

        let markdown = try convert(pdf)

        XCTAssert(markdown.contains("Page one paragraph."), "Got: \(markdown)")
        XCTAssert(markdown.contains("\n---\n\nPage two paragraph."), "Got: \(markdown)")
    }

    func testJoinsHyphenatedLineBreaks() throws {
        let pdf = try makePDF(
            named: "hyphenation.pdf",
            pages: [[
                DrawBlock(text: "micro-\nservice migration", fontSize: 18, origin: CGPoint(x: 72, y: 560)),
            ]]
        )

        let markdown = try convert(pdf)

        XCTAssert(markdown.contains("microservice migration"), "Got: \(markdown)")
        XCTAssertFalse(markdown.contains("micro- service"), "Got: \(markdown)")
    }

    func testFrontmatterIncludesSourceAndPageCount() throws {
        let pdf = try makePDF(
            named: "frontmatter.pdf",
            pages: [[
                DrawBlock(text: "Frontmatter body.", fontSize: 18, origin: CGPoint(x: 72, y: 640)),
            ]]
        )

        var options = ConversionOptions.default
        options.includeFrontmatter = true
        let markdown = try convert(pdf, options: options)

        XCTAssert(markdown.contains("source: \"frontmatter.pdf\""), "Got: \(markdown)")
        XCTAssert(markdown.contains("format: \"pdf\""), "Got: \(markdown)")
        XCTAssert(markdown.contains("pages: 1"), "Got: \(markdown)")
    }

    // MARK: - Helpers

    private func convert(_ input: URL, options: ConversionOptions = .default) throws -> String {
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }
        return try converter.convertToString(input: input, options: options)
    }

    private func makePDF(named fileName: String, pages: [[DrawBlock]]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-to-md-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(fileName)
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)

        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw TestError.cannotCreatePDFContext
        }
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw TestError.cannotCreatePDFContext
        }

        for page in pages {
            context.beginPDFPage(nil)
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext

            for block in page {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = block.lineSpacing
                let attributed = NSAttributedString(
                    string: block.text,
                    attributes: [
                        .font: block.font,
                        .paragraphStyle: style,
                    ]
                )
                if block.text.contains("\n") {
                    attributed.draw(in: CGRect(x: block.origin.x, y: block.origin.y, width: 468, height: 200))
                } else {
                    attributed.draw(at: block.origin)
                }
            }

            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }

        context.closePDF()
        try Data(referencing: data).write(to: url)
        return url
    }
}

private struct DrawBlock {
    let text: String
    let fontSize: CGFloat
    let origin: CGPoint
    var lineSpacing: CGFloat = 6

    var font: NSFont {
        NSFont(name: "Times New Roman", size: fontSize) ?? .systemFont(ofSize: fontSize)
    }
}

private enum TestError: Error {
    case cannotCreatePDFContext
}
