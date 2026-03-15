import Foundation
import CommonConverterSwift
import OOXMLSwift
@testable import WordToHTML

#if canImport(XCTest)
import XCTest

final class WordHTMLConverterTests: XCTestCase {
    private let converter = WordHTMLConverter()

    private func makeDocument(paragraphs: [Paragraph]) -> WordDocument {
        var doc = WordDocument()
        for paragraph in paragraphs {
            doc.appendParagraph(paragraph)
        }
        return doc
    }

    private func makeDocument(paragraph: Paragraph) -> WordDocument {
        makeDocument(paragraphs: [paragraph])
    }

    private func convert(_ document: WordDocument, options: ConversionOptions = .default) throws -> String {
        try converter.convertToString(document: document, options: options)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func temporaryDocx(from document: WordDocument, name: String = "test.docx") throws -> URL {
        let dir = try temporaryDirectory()
        let url = dir.appendingPathComponent(name)
        try DocxWriter.write(document, to: url)
        return url
    }

    func testBasicParagraph() throws {
        let html = try convert(makeDocument(paragraph: Paragraph(text: "Hello world")))
        XCTAssertTrue(html.contains("<p>Hello world</p>"), "Got: \(html)")
    }

    func testHeadingLevelOne() throws {
        var paragraph = Paragraph(text: "Title")
        paragraph.properties.style = "Heading1"

        let html = try convert(makeDocument(paragraph: paragraph))
        XCTAssertTrue(html.contains("<h1>Title</h1>"), "Got: \(html)")
    }

    func testHeadingLevelThree() throws {
        var paragraph = Paragraph(text: "Section")
        paragraph.properties.style = "Heading 3"

        let html = try convert(makeDocument(paragraph: paragraph))
        XCTAssertTrue(html.contains("<h3>Section</h3>"), "Got: \(html)")
    }

    func testInlineFormatting() throws {
        let runs = [
            Run(text: "bold", properties: RunProperties(bold: true)),
            Run(text: " "),
            Run(text: "italic", properties: RunProperties(italic: true)),
            Run(text: " "),
            Run(text: "gone", properties: RunProperties(strikethrough: true)),
        ]
        let html = try convert(makeDocument(paragraph: Paragraph(runs: runs)))

        XCTAssertTrue(html.contains("<strong>bold</strong>"), "Got: \(html)")
        XCTAssertTrue(html.contains("<em>italic</em>"), "Got: \(html)")
        XCTAssertTrue(html.contains("<del>gone</del>"), "Got: \(html)")
    }

    func testHTMLNativeInlineFormatting() throws {
        let runs = [
            Run(text: "u", properties: RunProperties(underline: .single)),
            Run(text: "2", properties: RunProperties(verticalAlign: .superscript)),
            Run(text: "mark", properties: RunProperties(highlight: .yellow)),
        ]
        let html = try convert(makeDocument(paragraph: Paragraph(runs: runs)))

        XCTAssertTrue(html.contains("<u>u</u>"), "Got: \(html)")
        XCTAssertTrue(html.contains("<sup>2</sup>"), "Got: \(html)")
        XCTAssertTrue(html.contains("<mark>mark</mark>"), "Got: \(html)")
    }

    func testExternalHyperlink() throws {
        var paragraph = Paragraph()
        paragraph.runs = [Run(text: "See ")]
        paragraph.hyperlinks = [Hyperlink(id: "h1", text: "Example", url: "https://example.com", relationshipId: "rId9")]

        var document = WordDocument()
        document.hyperlinkReferences = [HyperlinkReference(relationshipId: "rId9", url: "https://example.com")]
        document.appendParagraph(paragraph)

        let html = try convert(document)
        XCTAssertTrue(html.contains("<a href=\"https://example.com\">Example</a>"), "Got: \(html)")
    }

    func testInternalHyperlink() throws {
        var paragraph = Paragraph()
        paragraph.hyperlinks = [Hyperlink(id: "h1", text: "Jump", anchor: "target")]

        let html = try convert(makeDocument(paragraph: paragraph))
        XCTAssertTrue(html.contains("<a href=\"#target\">Jump</a>"), "Got: \(html)")
    }

    func testBulletList() throws {
        var first = Paragraph(text: "One")
        first.properties.numbering = NumberingInfo(numId: 1, level: 0)
        var second = Paragraph(text: "Two")
        second.properties.numbering = NumberingInfo(numId: 1, level: 0)

        var document = makeDocument(paragraphs: [first, second])
        var abstractNum = AbstractNum(abstractNumId: 0)
        abstractNum.levels = [Level(ilvl: 0, numFmt: .bullet, lvlText: "•", indent: 720)]
        document.numbering.abstractNums = [abstractNum]
        document.numbering.nums = [Num(numId: 1, abstractNumId: 0)]

        let html = try convert(document)
        XCTAssertTrue(html.contains("<ul>"), "Got: \(html)")
        XCTAssertTrue(html.contains("<li>One</li>"), "Got: \(html)")
        XCTAssertTrue(html.contains("<li>Two</li>"), "Got: \(html)")
    }

    func testOrderedNestedList() throws {
        var first = Paragraph(text: "Step 1")
        first.properties.numbering = NumberingInfo(numId: 2, level: 0)
        var nested = Paragraph(text: "Detail")
        nested.properties.numbering = NumberingInfo(numId: 2, level: 1)
        var second = Paragraph(text: "Step 2")
        second.properties.numbering = NumberingInfo(numId: 2, level: 0)

        var document = makeDocument(paragraphs: [first, nested, second])
        var abstractNum = AbstractNum(abstractNumId: 1)
        abstractNum.levels = [
            Level(ilvl: 0, numFmt: .decimal, lvlText: "%1.", indent: 720),
            Level(ilvl: 1, numFmt: .decimal, lvlText: "%2.", indent: 1440),
        ]
        document.numbering.abstractNums = [abstractNum]
        document.numbering.nums = [Num(numId: 2, abstractNumId: 1)]

        let html = try convert(document)
        XCTAssertTrue(html.contains("<ol>"), "Got: \(html)")
        XCTAssertTrue(html.contains("<li>Step 1"), "Got: \(html)")
        XCTAssertTrue(html.contains("<li>Detail</li>"), "Got: \(html)")
        XCTAssertTrue(html.contains("<li>Step 2</li>"), "Got: \(html)")
    }

    func testCodeBlockStyle() throws {
        var paragraph = Paragraph(text: "let x = 42")
        paragraph.properties.style = "Code"

        let html = try convert(makeDocument(paragraph: paragraph))
        XCTAssertTrue(html.contains("<pre><code>let x = 42</code></pre>"), "Got: \(html)")
    }

    func testBlockquoteStyle() throws {
        var paragraph = Paragraph(text: "Quoted")
        paragraph.properties.style = "Quote"

        let html = try convert(makeDocument(paragraph: paragraph))
        XCTAssertTrue(html.contains("<blockquote><p>Quoted</p></blockquote>"), "Got: \(html)")
    }

    func testPageBreakProducesHorizontalRule() throws {
        var paragraph = Paragraph()
        paragraph.hasPageBreak = true

        let html = try convert(makeDocument(paragraph: paragraph))
        XCTAssertTrue(html.contains("<hr />"), "Got: \(html)")
    }

    func testBasicTable() throws {
        let table = Table(rows: [
            TableRow(cells: [TableCell(text: "Header 1"), TableCell(text: "Header 2")]),
            TableRow(cells: [TableCell(text: "A"), TableCell(text: "B")]),
        ])
        var document = WordDocument()
        document.body.children.append(.table(table))

        let html = try convert(document)
        XCTAssertTrue(html.contains("<table>"), "Got: \(html)")
        XCTAssertTrue(html.contains("<th>Header 1</th>"), "Got: \(html)")
        XCTAssertTrue(html.contains("<td>A</td>"), "Got: \(html)")
    }

    func testInlineImageReference() throws {
        let drawing = Drawing(
            type: .inline,
            width: 914400,
            height: 914400,
            imageId: "rId5",
            name: "diagram",
            description: "Architecture diagram"
        )
        var run = Run(text: "")
        run.drawing = drawing

        var document = WordDocument()
        document.images = [ImageReference(id: "rId5", fileName: "figure.png", contentType: "image/png", data: Data([0x01, 0x02]))]
        document.appendParagraph(Paragraph(runs: [run]))

        let html = try convert(document)
        XCTAssertTrue(html.contains("<img src=\"figure.png\" alt=\"Architecture diagram\" />"), "Got: \(html)")
    }

    func testImageExtractionWhenFiguresDirectoryProvided() throws {
        let drawing = Drawing(
            type: .inline,
            width: 914400,
            height: 914400,
            imageId: "rId6",
            name: "photo",
            description: "Photo"
        )
        var run = Run(text: "")
        run.drawing = drawing

        var document = WordDocument()
        document.images = [ImageReference(id: "rId6", fileName: "photo.png", contentType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47]))]
        document.appendParagraph(Paragraph(runs: [run]))

        let base = try temporaryDirectory()
        let directory = base.appendingPathComponent("images", isDirectory: true)
        var options = ConversionOptions.default
        options.fidelity = .markdownWithFigures
        options.figuresDirectory = directory

        let html = try convert(document, options: options)
        XCTAssertTrue(html.contains("<img src=\"images/photo.png\" alt=\"Photo\" />"), "Got: \(html)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("photo.png").path))
    }

    func testFootnoteEmission() throws {
        var paragraph = Paragraph(text: "Text")
        paragraph.footnoteIds = [1]

        var document = WordDocument()
        document.footnotes.footnotes = [Footnote(id: 1, text: "A footnote.", paragraphIndex: 0)]
        document.appendParagraph(paragraph)

        let html = try convert(document)
        XCTAssertTrue(html.contains("href=\"#fn-1\""), "Got: \(html)")
        XCTAssertTrue(html.contains("<section class=\"footnotes\">"), "Got: \(html)")
        XCTAssertTrue(html.contains("A footnote."), "Got: \(html)")
    }

    func testFrontmatterIncludesMetadata() throws {
        var document = WordDocument()
        document.properties.title = "My Doc"
        document.properties.creator = "Author"
        document.appendParagraph(Paragraph(text: "content"))

        var options = ConversionOptions.default
        options.includeFrontmatter = true

        let html = try convert(document, options: options)
        XCTAssertTrue(html.contains("<!--"), "Got: \(html)")
        XCTAssertTrue(html.contains("title: My Doc"), "Got: \(html)")
        XCTAssertTrue(html.contains("author: Author"), "Got: \(html)")
    }

    func testConvertFromDocxURL() throws {
        var document = WordDocument()
        document.properties.title = "From File"
        document.appendParagraph(Paragraph(text: "Hello from docx"))

        let url = try temporaryDocx(from: document)
        let html = try converter.convertToString(input: url)

        XCTAssertTrue(html.contains("<title>From File</title>"), "Got: \(html)")
        XCTAssertTrue(html.contains("<p>Hello from docx</p>"), "Got: \(html)")
    }
}
#endif
