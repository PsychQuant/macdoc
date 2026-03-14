#if canImport(XCTest)
import XCTest
@testable import MDToWordSwift

final class MarkdownToWordConverterTests: XCTestCase {
    private let converter = MarkdownToWordConverter()

    func testFrontmatterHeadingAndInlineFormatting() throws {
        let markdown = """
        ---
        title: "Frontmatter Title"
        author: Jane Doe
        description: Converted from test
        ---

        # Visible Heading

        Hello **bold** _italic_ ~~gone~~ `code`.
        """

        let directory = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = try convert(markdown: markdown, in: directory)
        let documentXML = try archiveEntry(named: "word/document.xml", in: output)
        let coreXML = try archiveEntry(named: "docProps/core.xml", in: output)

        XCTAssertTrue(documentXML.contains("Heading1"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("Visible Heading"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("<w:b/>"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("<w:i/>"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("<w:strike/>"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("Menlo"), "Got: \(documentXML)")
        XCTAssertTrue(coreXML.contains("Frontmatter Title"), "Got: \(coreXML)")
        XCTAssertTrue(coreXML.contains("Jane Doe"), "Got: \(coreXML)")
    }

    func testListsCreateNumberingDefinitions() throws {
        let markdown = """
        - One
        - Two

        1. First
        2. Second
        """

        let directory = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = try convert(markdown: markdown, in: directory)
        let documentXML = try archiveEntry(named: "word/document.xml", in: output)
        let numberingXML = try archiveEntry(named: "word/numbering.xml", in: output)

        XCTAssertTrue(documentXML.contains("<w:numPr>"), "Got: \(documentXML)")
        XCTAssertTrue(numberingXML.contains("w:numFmt w:val=\"bullet\""), "Got: \(numberingXML)")
        XCTAssertTrue(numberingXML.contains("w:numFmt w:val=\"decimal\""), "Got: \(numberingXML)")
    }

    func testTablesRenderAsWordTables() throws {
        let markdown = """
        | Name | Value |
        |------|-------|
        | A    | 1     |
        | B    | 2     |
        """

        let directory = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = try convert(markdown: markdown, in: directory)
        let documentXML = try archiveEntry(named: "word/document.xml", in: output)

        XCTAssertTrue(documentXML.contains("<w:tbl>"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("Name"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("Value"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("A"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("B"), "Got: \(documentXML)")
    }

    func testLinksCreateRelationships() throws {
        let markdown = "See [Docs](https://example.com/docs) for details."

        let directory = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = try convert(markdown: markdown, in: directory)
        let documentXML = try archiveEntry(named: "word/document.xml", in: output)
        let relsXML = try archiveEntry(named: "word/_rels/document.xml.rels", in: output)

        XCTAssertTrue(documentXML.contains("<w:hyperlink r:id="), "Got: \(documentXML)")
        XCTAssertTrue(relsXML.contains("https://example.com/docs"), "Got: \(relsXML)")
        XCTAssertTrue(relsXML.contains("TargetMode=\"External\""), "Got: \(relsXML)")
    }

    func testFencedCodeBlocksUseMonospaceAndShading() throws {
        let markdown = """
        ```swift
        let x = 1
        print(x)
        ```
        """

        let directory = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = try convert(markdown: markdown, in: directory)
        let documentXML = try archiveEntry(named: "word/document.xml", in: output)

        XCTAssertTrue(documentXML.contains("Menlo"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("let x = 1"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("print(x)"), "Got: \(documentXML)")
        XCTAssertTrue(documentXML.contains("F7F7F7"), "Got: \(documentXML)")
    }

    private func makeWorkspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-to-word-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func convert(markdown: String, in directory: URL) throws -> URL {
        let input = directory.appendingPathComponent("fixture.md")
        let output = directory.appendingPathComponent("fixture.docx")
        try markdown.write(to: input, atomically: true, encoding: .utf8)
        try converter.convertToFile(input: input, output: output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        return output
    }

    private func archiveEntry(named path: String, in archiveURL: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archiveURL.path, path]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let errorText = String(decoding: errorData, as: UTF8.self)
            XCTFail("Failed to read archive entry \(path): \(errorText)")
            return ""
        }

        return String(decoding: data, as: UTF8.self)
    }
}
#endif
