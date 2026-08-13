#if canImport(XCTest)
import XCTest
@testable import MDToWord

final class MarkdownMathScannerTests: XCTestCase {
    func testInlineRecognitionBoundaryTable() throws {
        let cases: [(source: String, count: Int, retained: [String])] = [
            ("Before $x^2$ after", 1, ["Before ", " after"]),
            (#"Price \$5"#, 0, [#"\$5"#]),
            ("Code `$x$` end", 0, ["$x$"]),
            ("[link](https://example.com/$x$)", 0, ["https://example.com/$x$"]),
            ("![image](images/$x$.png)", 0, ["images/$x$.png"]),
            ("<https://example.com/$x$>", 0, ["$x$"]),
            ("[ref]: https://example.com/$x$\n\n[link][ref]", 0, ["https://example.com/$x$"]),
            ("Unmatched $x", 0, ["$x"]),
            ("$ spaced $", 0, ["$ spaced $"]),
            ("Price $5.00", 0, ["$5.00"]),
        ]

        for testCase in cases {
            let result = try MarkdownMathScanner().scan(testCase.source)
            XCTAssertEqual(result.tokens.count, testCase.count, "Source: \(testCase.source)")
            for text in testCase.retained {
                XCTAssertTrue(
                    result.markdown.contains(text),
                    "Expected retained text \(text) in \(result.markdown)"
                )
            }
        }
    }

    func testInlineTokenRecordsBodyKindAndOneBasedLocation() throws {
        let result = try MarkdownMathScanner().scan("First\n\nA $x^2$ B")

        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].latex, "x^2")
        XCTAssertEqual(result.tokens[0].kind, .inline)
        XCTAssertEqual(result.tokens[0].line, 3)
        XCTAssertEqual(result.tokens[0].column, 3)
        XCTAssertEqual(result.markdown, "First\n\nA \(result.tokens[0].placeholder) B")
    }

    func testCRLFCountsAsOneLogicalLine() throws {
        let result = try MarkdownMathScanner().scan("First\r\nA $x$ B")

        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].line, 2)
        XCTAssertEqual(result.tokens[0].column, 3)
    }

    func testOneLineDisplayFormulaIsRecognized() throws {
        let result = try MarkdownMathScanner().scan(#"  $$\frac{a}{b}$$  "#)

        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].kind, .display)
        XCTAssertEqual(result.tokens[0].latex, #"\frac{a}{b}"#)
        XCTAssertEqual(result.tokens[0].line, 1)
        XCTAssertEqual(result.tokens[0].column, 3)
    }

    func testMultilineDisplayFormulaIsRecognized() throws {
        let source = #"""
        $$
        \frac{a}{b}
        $$
        """#
        let result = try MarkdownMathScanner().scan(source)

        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].kind, .display)
        XCTAssertEqual(result.tokens[0].latex, #"\frac{a}{b}"#)
        XCTAssertEqual(result.tokens[0].line, 1)
        XCTAssertEqual(result.tokens[0].column, 1)
        XCTAssertEqual(result.markdown, result.tokens[0].placeholder)
    }

    func testMultilineDisplayPreservesFollowingParagraphBoundary() throws {
        let source = "Before\n\n$$\nx\n$$\n\nAfter"
        let result = try MarkdownMathScanner().scan(source)

        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(
            result.markdown,
            "Before\n\n\(result.tokens[0].placeholder)\n\nAfter"
        )
    }

    func testFencedCodeRemainsNonMath() throws {
        let source = """
        ```swift
        let inline = "$x$"
        let display = "$$y$$"
        ```
        """
        let result = try MarkdownMathScanner().scan(source)

        XCTAssertTrue(result.tokens.isEmpty)
        XCTAssertEqual(result.markdown, source)
    }

    func testDisplayDelimiterMixedWithTextIsRejected() {
        XCTAssertThrowsError(try MarkdownMathScanner().scan("before $$x$$ after")) { error in
            XCTAssertEqual(
                error as? MarkdownMathScanner.ScanError,
                .misplacedDisplayFormula(line: 1, column: 8)
            )
        }
    }

    func testPlaceholderNeverOverwritesCallerText() throws {
        let scanner = MarkdownMathScanner(
            markerPrefix: "MDTOWORDMATHPLACEHOLDER",
            markerNonce: "FIXED"
        )
        let source = "Keep MDTOWORDMATHPLACEHOLDERFIXED0TOKEN and convert $x$"
        let result = try scanner.scan(source)

        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertNotEqual(result.tokens[0].placeholder, "MDTOWORDMATHPLACEHOLDERFIXED0TOKEN")
        XCTAssertTrue(result.markdown.contains("MDTOWORDMATHPLACEHOLDERFIXED0TOKEN"))
        XCTAssertTrue(result.markdown.contains(result.tokens[0].placeholder))
    }
}
#endif
