import Foundation
import OOXMLSwift
@testable import HTMLToWord

#if canImport(XCTest)
import XCTest

final class HTMLToWordConverterTests: XCTestCase {
    private let converter = HTMLToWordConverter()
    private var cleanupURLs: [URL] = []

    override func tearDown() {
        for url in cleanupURLs {
            try? FileManager.default.removeItem(at: url)
        }
        cleanupURLs.removeAll()
        super.tearDown()
    }

    func testConvertToStringStreamsDocumentXML() throws {
        let inputURL = try makeHTMLFile(
            named: "basic.html",
            html: """
            <!doctype html>
            <html>
              <head><title>Sample</title></head>
              <body><h1>Heading</h1><p>Hello world</p></body>
            </html>
            """
        )

        let xml = try converter.convertToString(input: inputURL)

        XCTAssertTrue(xml.contains("<w:document"), "Got: \(xml)")
        XCTAssertTrue(xml.contains("Heading"), "Got: \(xml)")
        XCTAssertTrue(xml.contains("Hello world"), "Got: \(xml)")
    }

    func testConvertToFileCreatesDocxWithCoreMetadata() throws {
        let inputURL = try makeHTMLFile(
            named: "article.html",
            html: """
            <!doctype html>
            <html>
              <head>
                <title>Research Note</title>
                <meta name="author" content="Che Cheng" />
              </head>
              <body><p>Body text</p></body>
            </html>
            """
        )
        let outputURL = inputURL.deletingPathExtension().appendingPathExtension("docx")

        try converter.convertToFile(input: inputURL, output: outputURL)
        let extracted = try extractArchive(outputURL)

        let documentXML = try readFile(extracted.appendingPathComponent("word/document.xml"))
        let coreXML = try readFile(extracted.appendingPathComponent("docProps/core.xml"))

        XCTAssertTrue(documentXML.contains("Body text"), "Got: \(documentXML)")
        XCTAssertTrue(coreXML.contains("Research Note"), "Got: \(coreXML)")
        XCTAssertTrue(coreXML.contains("Che Cheng"), "Got: \(coreXML)")
    }

    func testInlineFormattingMapsToOOXMLRunProperties() throws {
        let inputURL = try makeHTMLFile(
            named: "inline.html",
            html: """
            <p>
              <strong>bold</strong>
              <em>italic</em>
              <u>under</u>
              <del>gone</del>
              H<sub>2</sub>O and x<sup>2</sup>
              <mark>hot</mark>
            </p>
            """
        )
        let outputURL = inputURL.deletingPathExtension().appendingPathExtension("docx")

        try converter.convertToFile(input: inputURL, output: outputURL)
        let extracted = try extractArchive(outputURL)
        let documentXML = try readFile(extracted.appendingPathComponent("word/document.xml"))

        XCTAssertTrue(documentXML.contains("<w:b/>"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("<w:i/>"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("<w:u w:val=\"single\"/>"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("<w:strike/>"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("w:vertAlign w:val=\"subscript\""), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("w:vertAlign w:val=\"superscript\""), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("<w:highlight w:val=\"yellow\"/>"), "Got: \(documentXML)")
    }

    func testListsProduceNumberingDefinitions() throws {
        let inputURL = try makeHTMLFile(
            named: "lists.html",
            html: """
            <ul>
              <li>First</li>
              <li>Second
                <ol>
                  <li>Nested one</li>
                </ol>
              </li>
            </ul>
            """
        )
        let outputURL = inputURL.deletingPathExtension().appendingPathExtension("docx")

        try converter.convertToFile(input: inputURL, output: outputURL)
        let extracted = try extractArchive(outputURL)
        let documentXML = try readFile(extracted.appendingPathComponent("word/document.xml"))
        let numberingXML = try readFile(extracted.appendingPathComponent("word/numbering.xml"))

        XCTAssertTrue(documentXML.contains("<w:numPr>"), "Got: \(documentXML)")
        XCTAssertTrue(numberingXML.contains("<w:numFmt w:val=\"bullet\"/>"), "Got: \(numberingXML)")
        XCTAssertTrue(numberingXML.contains("<w:numFmt w:val=\"decimal\"/>"), "Got: \(numberingXML)")
    }

    func testTableProducesWordTableXML() throws {
        let inputURL = try makeHTMLFile(
            named: "table.html",
            html: """
            <table>
              <tr><th>Header A</th><th>Header B</th></tr>
              <tr><td>Value 1</td><td>Value 2</td></tr>
            </table>
            """
        )
        let outputURL = inputURL.deletingPathExtension().appendingPathExtension("docx")

        try converter.convertToFile(input: inputURL, output: outputURL)
        let extracted = try extractArchive(outputURL)
        let documentXML = try readFile(extracted.appendingPathComponent("word/document.xml"))

        XCTAssertTrue(documentXML.contains("<w:tbl>"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("Header A"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("Value 2"), "Got: \(documentXML)")
    }

    func testHyperlinksProduceDocumentRelationships() throws {
        let inputURL = try makeHTMLFile(
            named: "links.html",
            html: """
            <p>Visit <a href="https://example.com">Example</a> now.</p>
            """
        )
        let outputURL = inputURL.deletingPathExtension().appendingPathExtension("docx")

        try converter.convertToFile(input: inputURL, output: outputURL)
        let extracted = try extractArchive(outputURL)
        let documentXML = try readFile(extracted.appendingPathComponent("word/document.xml"))
        let relsXML = try readFile(extracted.appendingPathComponent("word/_rels/document.xml.rels"))

        XCTAssertTrue(documentXML.contains("<w:hyperlink r:id=\"rIdHTMLLink1\""), "Got: \(documentXML)")
        XCTAssertTrue(relsXML.contains("https://example.com"), "Got: \(relsXML)")
    }

    func testBlockquoteAndPreformattedContentMapToIndentAndBreaks() throws {
        let inputURL = try makeHTMLFile(
            named: "quote-code.html",
            html: """
            <blockquote><p>Quoted text</p></blockquote>
            <pre><code>line 1\nline 2</code></pre>
            """
        )
        let outputURL = inputURL.deletingPathExtension().appendingPathExtension("docx")

        try converter.convertToFile(input: inputURL, output: outputURL)
        let extracted = try extractArchive(outputURL)
        let documentXML = try readFile(extracted.appendingPathComponent("word/document.xml"))

        XCTAssertTrue(documentXML.contains("<w:ind w:left=\"720\""), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("<w:br/>"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("Menlo"), "Got: \(documentXML)")
    }

    func testTitleFallsBackToSourceFilename() throws {
        let inputURL = try makeHTMLFile(
            named: "fallback-title.html",
            html: "<p>No title tag here</p>"
        )

        let document = try converter.convertToDocument(input: inputURL)
        XCTAssertEqual(document.properties.title, "fallback-title")
    }

    private func makeHTMLFile(named name: String, html: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cleanupURLs.append(directory)

        let fileURL = directory.appendingPathComponent(name)
        try html.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func extractArchive(_ archiveURL: URL) throws -> URL {
        let extracted = try ZipHelper.unzip(archiveURL)
        cleanupURLs.append(extracted)
        return extracted
    }

    private func readFile(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
#endif
