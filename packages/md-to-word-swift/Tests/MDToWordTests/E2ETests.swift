import XCTest
@testable import MDToWord
import OOXMLSwift
import WordToMD
import CommonConverterSwift

/// End-to-End round-trip tests starting from .docx files.
///
/// Pipeline:
/// ```
/// DocxWriter.write(doc₀) → .docx
/// → DocxReader.read() → WordDocument₁
/// → WordConverter → MD₁
/// → MarkdownToWordConverter → WordDocument₂
/// → WordConverter → MD₂
/// → assert MD₁ == MD₂ (retraction)
/// ```
final class E2ETests: XCTestCase {

    private var tempDir: URL!
    private let forward = WordConverter()
    private let reverse = MarkdownToWordConverter()

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("E2ETests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    /// Full E2E pipeline: WordDocument → .docx → WordDocument → MD₁ → Word → MD₂
    /// Returns (MD₁, MD₂) for comparison.
    private func e2eRoundTrip(
        _ doc: WordDocument,
        options: ConversionOptions = .default
    ) throws -> (md1: String, md2: String) {
        // 1. Write to .docx
        let docxURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).docx")
        try DocxWriter.write(doc, to: docxURL)

        // 2. Read back
        let readDoc = try DocxReader.read(from: docxURL)

        // 3. Convert to MD₁
        let md1 = try forward.convertToString(document: readDoc, options: options)

        // 4. Convert MD₁ → WordDocument
        let wordDoc2 = try reverse.convertMarkdown(md1)

        // 5. Convert back to MD₂
        let md2 = try forward.convertToString(document: wordDoc2, options: options)

        return (normalize(md1), normalize(md2))
    }

    /// Normalize markdown for comparison
    private func normalize(_ md: String) -> String {
        let lines = md.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var result: [String] = []
        var lastWasEmpty = false
        for line in lines {
            if line.isEmpty {
                if !lastWasEmpty {
                    result.append(line)
                }
                lastWasEmpty = true
            } else {
                result.append(line)
                lastWasEmpty = false
            }
        }

        return result.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - E2E Tests

    func testE2E_SimpleParagraph() throws {
        var doc = WordDocument()
        doc.body.children = [.paragraph(Paragraph(text: "Hello World"))]

        let (md1, md2) = try e2eRoundTrip(doc)
        XCTAssertEqual(md1, md2)
        XCTAssertTrue(md1.contains("Hello World"))
    }

    func testE2E_Headings() throws {
        var doc = WordDocument()
        doc.styles = Style.defaultStyles

        for level in 1...3 {
            var props = ParagraphProperties()
            props.style = "Heading\(level)"
            doc.body.children.append(.paragraph(Paragraph(text: "Heading \(level)", properties: props)))
        }

        let (md1, md2) = try e2eRoundTrip(doc)
        XCTAssertEqual(md1, md2)
        XCTAssertTrue(md1.contains("# Heading 1"))
        XCTAssertTrue(md1.contains("## Heading 2"))
        XCTAssertTrue(md1.contains("### Heading 3"))
    }

    func testE2E_Formatting() throws {
        var doc = WordDocument()
        var boldProps = RunProperties()
        boldProps.bold = true
        var italicProps = RunProperties()
        italicProps.italic = true

        doc.body.children = [.paragraph(Paragraph(runs: [
            Run(text: "bold", properties: boldProps),
            Run(text: " normal "),
            Run(text: "italic", properties: italicProps)
        ]))]

        let (md1, md2) = try e2eRoundTrip(doc)
        XCTAssertEqual(md1, md2)
        XCTAssertTrue(md1.contains("**bold**"))
        // italic may be rendered as *italic* or _italic_
        XCTAssertTrue(md1.contains("italic"))
    }

    func testE2E_Lists() throws {
        var doc = WordDocument()
        let bulletId = doc.numbering.createBulletList()
        let numId = doc.numbering.createNumberedList()

        // Bullet items
        for text in ["Apple", "Banana"] {
            var props = ParagraphProperties()
            props.numbering = NumberingInfo(numId: bulletId, level: 0)
            doc.body.children.append(.paragraph(Paragraph(text: text, properties: props)))
        }

        // Separator
        doc.body.children.append(.paragraph(Paragraph(text: "")))

        // Numbered items
        for text in ["First", "Second"] {
            var props = ParagraphProperties()
            props.numbering = NumberingInfo(numId: numId, level: 0)
            doc.body.children.append(.paragraph(Paragraph(text: text, properties: props)))
        }

        let (md1, md2) = try e2eRoundTrip(doc)
        XCTAssertEqual(md1, md2)
        XCTAssertTrue(md1.contains("Apple"))
        XCTAssertTrue(md1.contains("First"))
    }

    func testE2E_Table() throws {
        var doc = WordDocument()
        var headerRowProps = TableRowProperties()
        headerRowProps.isHeader = true
        let table = Table(rows: [
            TableRow(cells: [TableCell(text: "Name"), TableCell(text: "Value")], properties: headerRowProps),
            TableRow(cells: [TableCell(text: "A"), TableCell(text: "1")]),
            TableRow(cells: [TableCell(text: "B"), TableCell(text: "2")])
        ])
        doc.body.children = [.table(table)]

        let (md1, md2) = try e2eRoundTrip(doc)
        XCTAssertEqual(md1, md2)
        XCTAssertTrue(md1.contains("Name"))
        XCTAssertTrue(md1.contains("|"))
    }

    func testE2E_Footnotes() throws {
        var doc = WordDocument()
        doc.footnotes.footnotes.append(Footnote(id: 1, text: "A footnote explanation", paragraphIndex: 0))
        var para = Paragraph(text: "Text with footnote")
        para.footnoteIds = [1]
        doc.body.children = [.paragraph(para)]

        // Note: DocxReader doesn't parse footnotes, so MD₁ won't have footnotes.
        // This test verifies the pipeline doesn't crash and produces consistent output.
        let (md1, md2) = try e2eRoundTrip(doc)
        XCTAssertEqual(md1, md2)
    }

    func testE2E_MixedContent() throws {
        var doc = WordDocument()
        doc.styles = Style.defaultStyles

        // Heading
        var h1Props = ParagraphProperties()
        h1Props.style = "Heading1"
        doc.body.children.append(.paragraph(Paragraph(text: "Document Title", properties: h1Props)))

        // Normal paragraph with formatting
        var boldProps = RunProperties()
        boldProps.bold = true
        doc.body.children.append(.paragraph(Paragraph(runs: [
            Run(text: "This is "),
            Run(text: "important", properties: boldProps),
            Run(text: " text.")
        ])))

        // Table
        let table = Table(rows: [
            TableRow(cells: [TableCell(text: "Key"), TableCell(text: "Value")]),
            TableRow(cells: [TableCell(text: "A"), TableCell(text: "1")])
        ])
        doc.body.children.append(.table(table))

        // Another paragraph
        doc.body.children.append(.paragraph(Paragraph(text: "End of document.")))

        let (md1, md2) = try e2eRoundTrip(doc)
        XCTAssertEqual(md1, md2)
        XCTAssertTrue(md1.contains("# Document Title"))
        XCTAssertTrue(md1.contains("**important**"))
        XCTAssertTrue(md1.contains("End of document."))
    }

    // MARK: - Tier 3 Metadata Pipeline

    func testE2E_Tier3Metadata() throws {
        var doc = WordDocument()
        doc.properties.title = "Test Document"
        doc.properties.creator = "Author"

        // Paragraph with alignment (Layer C property)
        var props = ParagraphProperties()
        props.alignment = .center
        doc.body.children = [.paragraph(Paragraph(text: "Centered text", properties: props))]

        // Write .docx
        let docxURL = tempDir.appendingPathComponent("tier3.docx")
        try DocxWriter.write(doc, to: docxURL)

        // Read back
        let readDoc = try DocxReader.read(from: docxURL)

        // Convert to MD + YAML (Tier 3)
        let metaURL = tempDir.appendingPathComponent("test.meta.yaml")
        var options = ConversionOptions(fidelity: .marker, metadataOutput: metaURL)
        let md = try forward.convertToString(document: readDoc, options: options)

        // Verify YAML was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: metaURL.path))

        // Verify MD content
        XCTAssertTrue(md.contains("Centered text"))

        // Verify YAML content
        let yamlContent = try String(contentsOf: metaURL, encoding: .utf8)
        XCTAssertTrue(yamlContent.contains("version:"))
        XCTAssertTrue(yamlContent.contains("alignment: center"))
    }

    func testE2E_Tier3MetadataRestoration() throws {
        var doc = WordDocument()
        doc.styles = Style.defaultStyles

        // Create a document with Layer C properties
        var runProps = RunProperties()
        runProps.fontName = "Arial"
        runProps.fontSize = 28
        runProps.color = "FF0000"
        var paraProps = ParagraphProperties()
        paraProps.alignment = .center
        doc.body.children = [.paragraph(Paragraph(
            runs: [Run(text: "Styled text", properties: runProps)],
            properties: paraProps
        ))]

        // Write .docx
        let docxURL = tempDir.appendingPathComponent("tier3-restore.docx")
        try DocxWriter.write(doc, to: docxURL)

        // Read back
        let readDoc = try DocxReader.read(from: docxURL)

        // Convert to MD + YAML
        let metaURL = tempDir.appendingPathComponent("restore.meta.yaml")
        var options = ConversionOptions(fidelity: .marker, metadataOutput: metaURL)
        let md = try forward.convertToString(document: readDoc, options: options)

        // Now restore: MD + YAML → Word
        let metadata = try MetadataReader.read(from: metaURL)
        let restoredDoc = try reverse.convertMarkdown(md)

        // Convert restored doc back to MD + YAML
        let metaURL2 = tempDir.appendingPathComponent("restore2.meta.yaml")
        var options2 = ConversionOptions(fidelity: .marker, metadataOutput: metaURL2)
        let md2 = try forward.convertToString(document: restoredDoc, options: options2)

        // Verify MD is consistent
        XCTAssertEqual(normalize(md), normalize(md2))

        // Verify YAML alignment was restored
        let yaml2 = try String(contentsOf: metaURL2, encoding: .utf8)
        XCTAssertTrue(yaml2.contains("alignment: center"))
    }

    // MARK: - Edge Cases

    func testE2E_EmptyDocument() throws {
        let doc = WordDocument()
        let docxURL = tempDir.appendingPathComponent("empty.docx")
        try DocxWriter.write(doc, to: docxURL)

        let readDoc = try DocxReader.read(from: docxURL)
        let md = try forward.convertToString(document: readDoc)

        // Empty document should produce empty or minimal markdown
        XCTAssertEqual(md.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    func testE2E_XMLSpecialCharacters() throws {
        // Use characters that survive both XML and Markdown round-trip
        var doc = WordDocument()
        doc.body.children = [.paragraph(Paragraph(text: "Price: $100 & tax = total"))]

        let (md1, md2) = try e2eRoundTrip(doc)
        XCTAssertEqual(md1, md2)
        XCTAssertTrue(md1.contains("$100"))
        XCTAssertTrue(md1.contains("&"))
    }
}
