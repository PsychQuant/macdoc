import Foundation
import AppKit
import PDFKit
import CommonConverterSwift
import PDFToMDSwift

@main
struct PDFToMDSwiftSmokeTests {
    static func main() throws {
        let runner = Runner()
        try runner.runAll()
        print("pdf-to-md smoke tests: OK")
    }
}

private struct Runner {
    private let converter = PDFConverter()

    func runAll() throws {
        try convertsHeadingParagraphAndBulletList()
        try convertsOrderedListAndHardBreaks()
        try insertsPageBreakBetweenPages()
        try joinsHyphenatedLineBreaks()
        try frontmatterIncludesSourceAndPageCount()
    }

    private func convertsHeadingParagraphAndBulletList() throws {
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
        try expect(markdown.contains("# Quarterly Results"), "missing heading", markdown)
        try expect(markdown.contains("Revenue increased year over year. Margin expansion continued."), "missing paragraph", markdown)
        try expect(markdown.contains("- Revenue"), "missing first bullet", markdown)
        try expect(markdown.contains("- Margin"), "missing second bullet", markdown)
    }

    private func convertsOrderedListAndHardBreaks() throws {
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
        try expect(markdown.contains("Line one  \nLine two"), "missing hard break paragraph", markdown)
        try expect(markdown.contains("1. Collect data"), "missing ordered item 1", markdown)
        try expect(markdown.contains("2. Review output"), "missing ordered item 2", markdown)
    }

    private func insertsPageBreakBetweenPages() throws {
        let pdf = try makePDF(
            named: "page-breaks.pdf",
            pages: [
                [DrawBlock(text: "Page one paragraph.", fontSize: 18, origin: CGPoint(x: 72, y: 640))],
                [DrawBlock(text: "Page two paragraph.", fontSize: 18, origin: CGPoint(x: 72, y: 640))],
            ]
        )
        let markdown = try convert(pdf)
        try expect(markdown.contains("Page one paragraph."), "missing page 1 text", markdown)
        try expect(markdown.contains("\n---\n\nPage two paragraph."), "missing page break", markdown)
    }

    private func joinsHyphenatedLineBreaks() throws {
        let pdf = try makePDF(
            named: "hyphenation.pdf",
            pages: [[
                DrawBlock(text: "micro-\nservice migration", fontSize: 18, origin: CGPoint(x: 72, y: 560)),
            ]]
        )
        let markdown = try convert(pdf)
        try expect(markdown.contains("microservice migration"), "missing dehyphenated text", markdown)
        try expect(!markdown.contains("micro- service"), "still contains broken hyphenation", markdown)
    }

    private func frontmatterIncludesSourceAndPageCount() throws {
        let pdf = try makePDF(
            named: "frontmatter.pdf",
            pages: [[
                DrawBlock(text: "Frontmatter body.", fontSize: 18, origin: CGPoint(x: 72, y: 640)),
            ]]
        )
        var options = ConversionOptions.default
        options.includeFrontmatter = true
        let markdown = try convert(pdf, options: options)
        try expect(markdown.contains("source: \"frontmatter.pdf\""), "missing frontmatter source", markdown)
        try expect(markdown.contains("format: \"pdf\""), "missing frontmatter format", markdown)
        try expect(markdown.contains("pages: 1"), "missing frontmatter page count", markdown)
    }

    private func expect(_ condition: Bool, _ message: String, _ markdown: String) throws {
        guard condition else {
            throw SmokeTestError.failed("\(message)\n--- output ---\n\(markdown)")
        }
    }

    private func convert(_ input: URL, options: ConversionOptions = .default) throws -> String {
        defer { try? FileManager.default.removeItem(at: input.deletingLastPathComponent()) }
        return try converter.convertToString(input: input, options: options)
    }

    private func makePDF(named fileName: String, pages: [[DrawBlock]]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-to-md-smoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(fileName)
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)

        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw SmokeTestError.failed("cannot create PDF consumer")
        }
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw SmokeTestError.failed("cannot create PDF context")
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

private enum SmokeTestError: Error {
    case failed(String)
}
