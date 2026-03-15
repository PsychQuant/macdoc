import XCTest
@testable import MDToHTML

final class MarkdownConverterTests: XCTestCase {
    private let converter = MarkdownConverter()

    // MARK: - Headings

    func testHeadingLevels() {
        let md = """
        # H1
        ## H2
        ### H3
        """
        let html = converter.convertString(md)
        XCTAssert(html.contains("<h1>H1</h1>"), "Got: \(html)")
        XCTAssert(html.contains("<h2>H2</h2>"), "Got: \(html)")
        XCTAssert(html.contains("<h3>H3</h3>"), "Got: \(html)")
    }

    // MARK: - Paragraphs

    func testParagraph() {
        let md = "Hello **world**."
        let html = converter.convertString(md)
        XCTAssert(html.contains("<p>Hello <strong>world</strong>.</p>"), "Got: \(html)")
    }

    // MARK: - Inline Formatting

    func testEmphasis() {
        let html = converter.convertString("_italic_ and **bold** and ~~gone~~")
        XCTAssert(html.contains("<em>italic</em>"), "Got: \(html)")
        XCTAssert(html.contains("<strong>bold</strong>"), "Got: \(html)")
        XCTAssert(html.contains("<del>gone</del>"), "Got: \(html)")
    }

    func testInlineCode() {
        let html = converter.convertString("Use `let x = 1` here.")
        XCTAssert(html.contains("<code>let x = 1</code>"), "Got: \(html)")
    }

    // MARK: - Links and Images

    func testLink() {
        let html = converter.convertString("[Example](https://example.com)")
        XCTAssert(html.contains("<a href=\"https://example.com\">Example</a>"), "Got: \(html)")
    }

    func testImage() {
        let html = converter.convertString("![Alt](image.png)")
        XCTAssert(html.contains("<img src=\"image.png\" alt=\"Alt\">"), "Got: \(html)")
    }

    // MARK: - Lists

    func testUnorderedList() {
        let md = """
        - One
        - Two
        - Three
        """
        let html = converter.convertString(md)
        XCTAssert(html.contains("<ul>"), "Got: \(html)")
        XCTAssert(html.contains("<li>One</li>"), "Got: \(html)")
        XCTAssert(html.contains("<li>Two</li>"), "Got: \(html)")
    }

    func testOrderedList() {
        let md = """
        1. First
        2. Second
        """
        let html = converter.convertString(md)
        XCTAssert(html.contains("<ol>"), "Got: \(html)")
        XCTAssert(html.contains("<li>First</li>"), "Got: \(html)")
    }

    func testOrderedListCustomStart() {
        let md = """
        3. Third
        4. Fourth
        """
        let html = converter.convertString(md)
        XCTAssert(html.contains("start=\"3\""), "Got: \(html)")
    }

    // MARK: - Code Blocks

    func testCodeBlock() {
        let md = """
        ```swift
        let x = 1
        ```
        """
        let html = converter.convertString(md)
        XCTAssert(html.contains("class=\"language-swift\""), "Got: \(html)")
        XCTAssert(html.contains("let x = 1"), "Got: \(html)")
    }

    // MARK: - Blockquote

    func testBlockquote() {
        let md = "> Quoted text"
        let html = converter.convertString(md)
        XCTAssert(html.contains("<blockquote>"), "Got: \(html)")
        XCTAssert(html.contains("Quoted text"), "Got: \(html)")
    }

    // MARK: - Thematic Break

    func testThematicBreak() {
        let html = converter.convertString("---")
        XCTAssert(html.contains("<hr>"), "Got: \(html)")
    }

    // MARK: - Table

    func testTable() {
        let md = """
        | Name | Value |
        |------|-------|
        | A    | 1     |
        """
        let html = converter.convertString(md)
        XCTAssert(html.contains("<table>"), "Got: \(html)")
        XCTAssert(html.contains("<th>"), "Got: \(html)")
        XCTAssert(html.contains("<td>"), "Got: \(html)")
    }

    func testTableAlignment() {
        let md = """
        | Left | Center | Right |
        |:-----|:------:|------:|
        | a    | b      | c     |
        """
        let html = converter.convertString(md)
        XCTAssert(html.contains("<table>"), "Got: \(html)")
        // After fix: should use style="text-align: ..." not align="..."
        XCTAssert(html.contains("style=\"text-align: left;\""), "Expected style-based alignment, got: \(html)")
        XCTAssert(html.contains("style=\"text-align: center;\""), "Expected style-based alignment, got: \(html)")
        XCTAssert(html.contains("style=\"text-align: right;\""), "Expected style-based alignment, got: \(html)")
        XCTAssertFalse(html.contains("align=\""), "Should not use deprecated align attribute, got: \(html)")
    }

    // MARK: - Full Document Mode

    func testFullDocumentMode() {
        var opts = HTMLOptions.default
        opts.fullDocument = true
        let html = converter.convertString("Hello", options: opts)
        XCTAssert(html.contains("<!DOCTYPE html>"), "Got: \(html)")
        XCTAssert(html.contains("<html>"), "Got: \(html)")
        XCTAssert(html.contains("</html>"), "Got: \(html)")
    }

    // MARK: - File Loading (Issue 1)

    func testLoadSourceFileNotFound() {
        let bogus = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).md")
        XCTAssertThrowsError(try converter.convert(input: bogus)) { error in
            // Should propagate the file-not-found error, not silently swallow it.
            let nsError = error as NSError
            XCTAssert(
                nsError.domain == NSCocoaErrorDomain,
                "Expected Cocoa error for missing file, got: \(error)"
            )
        }
    }

    func testLoadSourceLatin1Fallback() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-to-html-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Write a file with Latin-1 encoding (contains a character not valid in UTF-8 context)
        let input = tmpDir.appendingPathComponent("latin1.md")
        let latin1Content = "# Caf\u{00E9}"
        let latin1Data = latin1Content.data(using: .isoLatin1)!
        try latin1Data.write(to: input)

        let html = try converter.convert(input: input)
        // Should successfully read the file via Latin-1 fallback
        XCTAssert(html.contains("Caf"), "Got: \(html)")
    }

    // MARK: - Task List (Issue 2)

    func testTaskListSimple() {
        let md = """
        - [ ] Todo
        - [x] Done
        """
        let html = converter.convertString(md)
        XCTAssert(html.contains("checkbox"), "Got: \(html)")
        XCTAssert(html.contains("Todo"), "Got: \(html)")
        XCTAssert(html.contains("checked"), "Got: \(html)")
    }
}
