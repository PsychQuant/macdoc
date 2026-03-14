import XCTest
import CommonConverterSwift
@testable import HTMLToMDSwift

final class HTMLConverterTests: XCTestCase {
    private let converter = HTMLConverter()

    private func convert(
        _ html: String,
        options: ConversionOptions = .default,
        fileName: String = "fixture.html"
    ) throws -> String {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("html-to-md-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let input = tmpDir.appendingPathComponent(fileName)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try html.write(to: input, atomically: true, encoding: .utf8)
        return try converter.convertToString(input: input, options: options)
    }

    func testHeadingsAndParagraphs() throws {
        let html = """
        <html><body>
          <h1>Main Title</h1>
          <p>Hello <strong>world</strong>.</p>
        </body></html>
        """
        let md = try convert(html)
        XCTAssert(md.contains("# Main Title"), "Got: \(md)")
        XCTAssert(md.contains("Hello **world**."), "Got: \(md)")
    }

    func testInlineFormattingAndLinks() throws {
        let html = """
        <p><em>Italic</em>, <b>bold</b>, <del>gone</del>, <code>x = 1</code>, <a href="https://example.com">link</a>.</p>
        """
        let md = try convert(html)
        XCTAssert(md.contains("_Italic_"), "Got: \(md)")
        XCTAssert(md.contains("**bold**"), "Got: \(md)")
        XCTAssert(md.contains("~~gone~~"), "Got: \(md)")
        XCTAssert(md.contains("`x = 1`"), "Got: \(md)")
        XCTAssert(md.contains("[link](https://example.com)"), "Got: \(md)")
    }

    func testUnorderedAndOrderedLists() throws {
        let html = """
        <body>
          <ul>
            <li>One</li>
            <li>Two<ul><li>Nested</li></ul></li>
          </ul>
          <ol>
            <li>First</li>
            <li>Second</li>
          </ol>
        </body>
        """
        let md = try convert(html)
        XCTAssert(md.contains("- One"), "Got: \(md)")
        XCTAssert(md.contains("- Two"), "Got: \(md)")
        XCTAssert(md.contains("  - Nested"), "Got: \(md)")
        XCTAssert(md.contains("1. First"), "Got: \(md)")
        XCTAssert(md.contains("2. Second"), "Got: \(md)")
    }

    func testCodeBlockPreservesWhitespaceAndLanguage() throws {
        let html = """
        <pre><code class="language-swift">let x = 1
            print(x)
        </code></pre>
        """
        let md = try convert(html)
        XCTAssert(md.contains("```swift"), "Got: \(md)")
        XCTAssert(md.contains("let x = 1\n    print(x)"), "Got: \(md)")
    }

    func testBlockquote() throws {
        let html = """
        <blockquote>
          <p>Quoted <strong>text</strong>.</p>
          <p>Second line.</p>
        </blockquote>
        """
        let md = try convert(html)
        XCTAssert(md.contains("> Quoted **text**."), "Got: \(md)")
        XCTAssert(md.contains("> Second line."), "Got: \(md)")
    }

    func testTable() throws {
        let html = """
        <table>
          <tr><th>Name</th><th>Value</th></tr>
          <tr><td>A</td><td>1</td></tr>
          <tr><td>B</td><td>2</td></tr>
        </table>
        """
        let md = try convert(html)
        XCTAssert(md.contains("| Name | Value |"), "Got: \(md)")
        XCTAssert(md.contains("| A | 1 |"), "Got: \(md)")
        XCTAssert(md.contains("| B | 2 |"), "Got: \(md)")
    }

    func testImagesAndHorizontalRule() throws {
        let html = """
        <body>
          <img src="images/chart.png" alt="Chart" title="Figure 1">
          <hr>
        </body>
        """
        let md = try convert(html)
        XCTAssert(md.contains("![Chart](images/chart.png \"Figure 1\")"), "Got: \(md)")
        XCTAssert(md.contains("* * *"), "Got: \(md)")
    }

    func testHardBreakOption() throws {
        let html = "<p>Line 1<br>Line 2</p>"
        var options = ConversionOptions.default
        options.hardLineBreaks = true
        let md = try convert(html, options: options)
        XCTAssert(md.contains("Line 1  \nLine 2"), "Got: \(md)")
    }

    func testHTMLExtensionsOptional() throws {
        let html = "<p><u>u</u> <sup>2</sup> <sub>n</sub> <mark>hi</mark></p>"
        let plain = try convert(html)
        XCTAssertFalse(plain.contains("<u>"), "Got: \(plain)")
        XCTAssert(plain.contains("u 2 n hi"), "Got: \(plain)")

        var options = ConversionOptions.default
        options.useHTMLExtensions = true
        let extended = try convert(html, options: options)
        XCTAssert(extended.contains("<u>u</u>"), "Got: \(extended)")
        XCTAssert(extended.contains("<sup>2</sup>"), "Got: \(extended)")
        XCTAssert(extended.contains("<sub>n</sub>"), "Got: \(extended)")
        XCTAssert(extended.contains("<mark>hi</mark>"), "Got: \(extended)")
    }

    func testFrontmatterIncludesTitleAndSource() throws {
        let html = "<html><head><title>Fixture</title></head><body><p>Hello</p></body></html>"
        var options = ConversionOptions.default
        options.includeFrontmatter = true
        let md = try convert(html, options: options, fileName: "doc.html")
        XCTAssert(md.contains("title: \"Fixture\""), "Got: \(md)")
        XCTAssert(md.contains("source: \"doc.html\""), "Got: \(md)")
        XCTAssert(md.contains("format: \"html\""), "Got: \(md)")
    }

    func testOrderedListWithStartAttribute() throws {
        let html = """
        <ol start="3">
          <li>Third</li>
          <li>Fourth</li>
        </ol>
        """
        let md = try convert(html)
        XCTAssert(md.contains("3. Third"), "Got: \(md)")
        XCTAssert(md.contains("4. Fourth"), "Got: \(md)")
    }
}
