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

    func testScannerDefersLogicalParagraphValidationToCommonMarkTree() throws {
        let sources = [
            "Before\n$$x$$\nAfter",
            "Before\n$$\nx\n$$\nAfter",
            "# Heading\n$$x$$\n\nAfter",
            "Before\n\n$$x$$\n# After",
            "- Before\n- $$x$$\n- After",
            "- $$\n  x\n  $$",
            "> $$\n> x\n> $$",
        ]

        for source in sources {
            let result = try MarkdownMathScanner().scan(source)
            XCTAssertEqual(result.tokens.count, 1, "Source: \(source)")
            guard result.tokens.count == 1 else { continue }
            XCTAssertEqual(result.tokens[0].kind, .display, "Source: \(source)")
            XCTAssertEqual(result.tokens[0].latex, "x", "Source: \(source)")
        }
    }

    func testReferenceDefinitionDestinationsRemainLiteralInContainersAndContinuations() throws {
        let sources = [
            "[ref]:\n  https://example.com/$x$\n\n[link][ref]",
            "> [ref]: https://example.com/$x$\n>\n> [link][ref]",
            "> [ref]:\n> https://example.com/$x$\n>\n> [link][ref]",
        ]

        for source in sources {
            let result = try MarkdownMathScanner().scan(source)
            XCTAssertTrue(result.tokens.isEmpty, "Source: \(source)")
            XCTAssertEqual(result.markdown, source)
        }
    }

    func testContainerFencesAndIndentedCodeRemainLiteral() throws {
        let sources = [
            "> ~~~text\n> $x$\n> ~~~",
            "- ~~~text\n  $x$\n  ~~~",
            "    $x$",
        ]

        for source in sources {
            let result = try MarkdownMathScanner().scan(source)
            XCTAssertTrue(result.tokens.isEmpty, "Source: \(source)")
            XCTAssertEqual(result.markdown, source)
        }
    }

    func testMultilineInlineLinkAndImageDestinationsRemainLiteral() throws {
        let sources = [
            "[link](\nhttps://example.com/$x$\n)",
            "[link](   /uri\n  \"title $x$\"  )",
            "[link](https://example.com/it's/$x$)",
            "![alt](\nimages/$x$.png\n)",
        ]

        for source in sources {
            let result = try MarkdownMathScanner().scan(source)
            XCTAssertTrue(result.tokens.isEmpty, "Source: \(source)")
            XCTAssertEqual(result.markdown, source)
        }
    }

    func testReferenceDefinitionOptionalTitlesRemainLiteral() throws {
        let sources = [
            "[ref]: https://example.com\n\"$x$\"",
            "[ref]: https://example.com\n'$x$'",
            "[ref]: https://example.com\n($x$)",
            "[ref]: https://example.com '\n$title$\n'",
        ]

        for source in sources {
            let result = try MarkdownMathScanner().scan(source)
            XCTAssertTrue(result.tokens.isEmpty, "Source: \(source)")
            XCTAssertEqual(result.markdown, source)
        }
    }

    func testDenseMarkerAllocationDoesNotRescanSourcePerToken() throws {
        let source = Array(repeating: "$x$", count: 10_000).joined(separator: " ")
        let started = Date()
        let result = try MarkdownMathScanner(markerNonce: "PERF").scan(source)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(result.tokens.count, 10_000)
        XCTAssertLessThan(elapsed, 1.5, "Dense marker allocation took \(elapsed) seconds")
    }
}
#endif
