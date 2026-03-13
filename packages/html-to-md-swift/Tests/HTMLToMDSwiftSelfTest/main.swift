import Foundation
import DocConverterSwift
import HTMLToMDSwift

struct Failure: Error, CustomStringConvertible {
    let description: String
}

let converter = HTMLConverter()
var passed = 0

func convert(
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

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw Failure(description: message)
    }
}

func test(_ name: String, _ body: () throws -> Void) throws {
    do {
        try body()
        passed += 1
        print("✓ \(name)")
        fflush(stdout)
    } catch {
        print("✗ \(name)")
        fflush(stdout)
        throw error
    }
}

@main
struct Runner {
    static func main() {
        do {
            try runAll()
            print("\nAll self-tests passed: \(passed)")
            fflush(stdout)
        } catch {
            fputs("Self-test failed: \(error)\n", stderr)
            exit(1)
        }
    }

    static func runAll() throws {
        try test("headingsAndParagraphs") {
            let html = """
            <html><body>
              <h1>Main Title</h1>
              <p>Hello <strong>world</strong>.</p>
            </body></html>
            """
            let md = try convert(html)
            try expect(md.contains("# Main Title"), "Got: \(md)")
            try expect(md.contains("Hello **world**."), "Got: \(md)")
        }

        try test("inlineFormattingAndLinks") {
            let html = """
            <p><em>Italic</em>, <b>bold</b>, <del>gone</del>, <code>x = 1</code>, <a href="https://example.com">link</a>.</p>
            """
            let md = try convert(html)
            try expect(md.contains("_Italic_"), "Got: \(md)")
            try expect(md.contains("**bold**"), "Got: \(md)")
            try expect(md.contains("~~gone~~"), "Got: \(md)")
            try expect(md.contains("`x = 1`"), "Got: \(md)")
            try expect(md.contains("[link](https://example.com)"), "Got: \(md)")
        }

        try test("unorderedAndOrderedLists") {
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
            try expect(md.contains("- One"), "Got: \(md)")
            try expect(md.contains("- Two"), "Got: \(md)")
            try expect(md.contains("  - Nested"), "Got: \(md)")
            try expect(md.contains("1. First"), "Got: \(md)")
            try expect(md.contains("2. Second"), "Got: \(md)")
        }

        try test("codeBlockPreservesWhitespaceAndLanguage") {
            let html = """
            <pre><code class="language-swift">let x = 1
                print(x)
            </code></pre>
            """
            let md = try convert(html)
            try expect(md.contains("```swift"), "Got: \(md)")
            try expect(md.contains("let x = 1\n    print(x)"), "Got: \(md)")
        }

        try test("blockquote") {
            let html = """
            <blockquote>
              <p>Quoted <strong>text</strong>.</p>
              <p>Second line.</p>
            </blockquote>
            """
            let md = try convert(html)
            try expect(md.contains("> Quoted **text**."), "Got: \(md)")
            try expect(md.contains("> Second line."), "Got: \(md)")
        }

        try test("table") {
            let html = """
            <table>
              <tr><th>Name</th><th>Value</th></tr>
              <tr><td>A</td><td>1</td></tr>
              <tr><td>B</td><td>2</td></tr>
            </table>
            """
            let md = try convert(html)
            try expect(md.contains("| Name | Value |"), "Got: \(md)")
            try expect(md.contains("| A | 1 |"), "Got: \(md)")
            try expect(md.contains("| B | 2 |"), "Got: \(md)")
        }

        try test("imagesAndHorizontalRule") {
            let html = """
            <body>
              <img src="images/chart.png" alt="Chart" title="Figure 1">
              <hr>
            </body>
            """
            let md = try convert(html)
            try expect(md.contains("![Chart](images/chart.png \"Figure 1\")"), "Got: \(md)")
            try expect(md.contains("---"), "Got: \(md)")
        }

        try test("hardBreakOption") {
            let html = "<p>Line 1<br>Line 2</p>"
            var options = ConversionOptions.default
            options.hardLineBreaks = true
            let md = try convert(html, options: options)
            try expect(md.contains("Line 1  \nLine 2"), "Got: \(md)")
        }

        try test("htmlExtensionsOptional") {
            let html = "<p><u>u</u> <sup>2</sup> <sub>n</sub> <mark>hi</mark></p>"
            let plain = try convert(html)
            try expect(!plain.contains("<u>"), "Got: \(plain)")
            try expect(plain.contains("u 2 n hi"), "Got: \(plain)")

            var options = ConversionOptions.default
            options.useHTMLExtensions = true
            let extended = try convert(html, options: options)
            try expect(extended.contains("<u>u</u>"), "Got: \(extended)")
            try expect(extended.contains("<sup>2</sup>"), "Got: \(extended)")
            try expect(extended.contains("<sub>n</sub>"), "Got: \(extended)")
            try expect(extended.contains("<mark>hi</mark>"), "Got: \(extended)")
        }

        try test("frontmatterIncludesTitleAndSource") {
            let html = "<html><head><title>Fixture</title></head><body><p>Hello</p></body></html>"
            var options = ConversionOptions.default
            options.includeFrontmatter = true
            let md = try convert(html, options: options, fileName: "doc.html")
            try expect(md.contains("title: \"Fixture\""), "Got: \(md)")
            try expect(md.contains("source: \"doc.html\""), "Got: \(md)")
            try expect(md.contains("format: \"html\""), "Got: \(md)")
        }
    }
}
