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

    func testEscapedDollarRecoveryRemainsBounded() throws {
        let source = String(repeating: #"\$x\$"#, count: 10_000)
        let clock = ContinuousClock()
        var result: MarkdownMathScanner.Result?

        let elapsed = try clock.measure {
            result = try MarkdownMathScanner().scan(source)
        }

        XCTAssertEqual(result?.tokens.count, 0)
        XCTAssertEqual(result?.markdown, source)
        XCTAssertLessThan(elapsed, .seconds(1))
    }

    func testEvenBackslashMathRecoveryRemainsBounded() throws {
        let source = String(repeating: #"\\$x\\$"#, count: 10_000)
        let clock = ContinuousClock()
        var result: MarkdownMathScanner.Result?

        let elapsed = try clock.measure {
            result = try MarkdownMathScanner().scan(source)
        }

        XCTAssertEqual(result?.tokens.count, 10_000)
        XCTAssertLessThan(elapsed, .seconds(1))
    }

    func testPublicMarkerPrefixLookupRemainsBounded() throws {
        let publicPrefix = MarkdownMathScanner.defaultMarkerPrefix
        let scanned = try MarkdownMathScanner(markerNonce: "FIXED").scan("$x$ and $y$")
        let tokens = Dictionary(uniqueKeysWithValues: scanned.tokens.map { token in
            (
                token.placeholder,
                RenderedMarkdownMathToken(
                    placeholder: token.placeholder,
                    omml: "<m:r/>",
                    kind: token.kind,
                    line: token.line,
                    column: token.column
                )
            )
        })
        let text = String(repeating: publicPrefix, count: 10_000)
        let searchPrefix = scanned.placeholderSearchPrefix
        let clock = ContinuousClock()
        var match: (range: Range<String.Index>, token: RenderedMarkdownMathToken)? = nil

        let elapsed = clock.measure {
            match = MarkdownInlineMathMatcher.nextMatch(
                in: text,
                from: text.startIndex,
                tokensByPlaceholder: tokens,
                searchPrefix: searchPrefix,
                maximumPlaceholderLength: tokens.keys.map(\.count).max() ?? 0
            )
        }

        XCTAssertTrue(try XCTUnwrap(searchPrefix).contains("FIXED"))
        XCTAssertFalse(try XCTUnwrap(searchPrefix).contains("0TOKEN"))
        XCTAssertNil(match)
        XCTAssertLessThan(elapsed, .seconds(1))
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

    func testUnmatchedVisibleDisplayDoesNotPairWithOpaqueCodeDelimiter() throws {
        let source = "Unmatched $$\n\n```text\n$$\n```"
        let result = try MarkdownMathScanner().scan(source)

        XCTAssertTrue(result.tokens.isEmpty)
        XCTAssertEqual(result.markdown, source)
    }

    func testUnmatchedDisplayDoesNotConsumeLaterCompleteDisplay() throws {
        let source = "Unmatched $$ here\n\n$$x$$\n"
        let result = try MarkdownMathScanner().scan(source)

        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].kind, .display)
        XCTAssertEqual(result.tokens[0].latex, "x")
        XCTAssertTrue(result.markdown.hasPrefix("Unmatched $$ here\n\n"))
        XCTAssertTrue(result.markdown.contains(result.tokens[0].placeholder))
    }

    func testUnmatchedDisplayIgnoresLaterOpaqueDoubleDollars() throws {
        let sources = [
            "Unmatched $$ here\n\nCode `$$x$$`\n",
            "Unmatched $$ here\n\n[link](https://example.com/$$x$$)\n",
            "Unmatched $$ here\n\n<span title=\"$$x$$\">text</span>\n",
        ]

        for source in sources {
            let result = try MarkdownMathScanner().scan(source)
            XCTAssertTrue(result.tokens.isEmpty, "Source: \(source)")
            XCTAssertEqual(result.markdown, source, "Source: \(source)")
        }
    }

    func testMixedUnmatchedDisplaysRemainLiteralBeforeCompleteDisplay() throws {
        let source = "First unmatched $$ here\n\nSecond unmatched $$ there\n\n$$x$$\n"
        let result = try MarkdownMathScanner().scan(source)

        XCTAssertEqual(result.tokens.count, 1)
        XCTAssertEqual(result.tokens[0].kind, .display)
        XCTAssertTrue(result.markdown.contains("First unmatched $$ here"))
        XCTAssertTrue(result.markdown.contains("Second unmatched $$ there"))
    }

    func testMixedDisplayReportsItsOwnLocationAfterUnmatchedLiteral() {
        let source = "First $$ here\n\nbefore $$x$$ after"

        XCTAssertThrowsError(try MarkdownMathScanner().scan(source)) { error in
            XCTAssertEqual(
                error as? MarkdownMathScanner.ScanError,
                .misplacedDisplayFormula(line: 3, column: 8)
            )
        }
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

    func testOriginalCommonMarkParagraphGatesDisplayRecognition() throws {
        let rejected: [(source: String, line: Int, column: Int)] = [
            ("Before\n$$x$$\nAfter", 2, 1),
            ("Before\n$$\nx\n$$\nAfter", 2, 1),
            ("$$\n\nx\n\n$$", 1, 1),
            ("- $$\n- x\n- $$", 1, 3),
            ("> $$\nx\n$$", 1, 3),
        ]

        for testCase in rejected {
            XCTAssertThrowsError(
                try MarkdownMathScanner().scan(testCase.source),
                "Source: \(testCase.source)"
            ) { error in
                XCTAssertEqual(
                    error as? MarkdownMathScanner.ScanError,
                    .misplacedDisplayFormula(line: testCase.line, column: testCase.column),
                    "Source: \(testCase.source)"
                )
            }
        }

        let accepted = [
            "# Heading\n$$x$$\n\nAfter",
            "Before\n\n$$x$$\n# After",
            "- Before\n- $$x$$\n- After",
            "- $$\n  x\n  $$",
            "> $$\n> x\n> $$",
        ]

        for source in accepted {
            let result = try MarkdownMathScanner().scan(source)
            XCTAssertEqual(result.tokens.count, 1, "Source: \(source)")
            guard result.tokens.count == 1 else { continue }
            XCTAssertEqual(result.tokens[0].kind, .display, "Source: \(source)")
            XCTAssertEqual(result.tokens[0].latex, "x", "Source: \(source)")
        }
    }

    func testOriginalCommonMarkOpaqueAndFormattingRangesRemainLiteral() throws {
        let sources = [
            "<!--\n$x$\n-->",
            "<div>\n$x$\n</div>",
            #"<span title="> $x$">text</span>"#,
            "$*x*$",
            "$**x**$",
        ]

        for source in sources {
            let result = try MarkdownMathScanner().scan(source)
            XCTAssertTrue(result.tokens.isEmpty, "Source: \(source)")
            XCTAssertEqual(result.markdown, source)
        }
    }

    func testInvalidHTMLLikeVisibleTextRemainsMathEligible() throws {
        let sources = [
            "Visible <span $x$> tail",
            "Visible <$x$> tail",
            "Visible <span \"$x$\"> tail </span>",
            "Visible <span ?=\"$x$\"> tail </span>",
            "Visible <span title=\"$x$\" ?> tail </span>",
            "Visible <span foo=bar=baz title=\"$x$\"> tail </span>",
            "Visible <span title=\"$x$\"foo=\"bar\"> tail </span>",
        ]
        for source in sources {
            let result = try MarkdownMathScanner().scan(source)

            XCTAssertEqual(result.tokens.count, 1, "Source: \(source)")
            XCTAssertEqual(result.tokens.first?.latex, "x", "Source: \(source)")
            XCTAssertTrue(
                result.markdown.contains(try XCTUnwrap(result.tokens.first).placeholder),
                "Source: \(source)"
            )
        }
    }

    func testUnterminatedHTMLLikePrefixesDoNotRescanLineSuffixes() throws {
        let source = String(repeating: "<a", count: 10_000)
        let clock = ContinuousClock()

        let elapsed = try clock.measure {
            _ = try MarkdownMathScanner().scan(source)
        }

        XCTAssertLessThan(elapsed, .seconds(1.5), "Elapsed: \(elapsed)")
    }

    func testMathTokenConsumptionRequiresExactlyOneCarrier() throws {
        let token = RenderedMarkdownMathToken(
            placeholder: "?TOKEN?",
            omml: "<m:r/>",
            kind: .inline,
            line: 7,
            column: 9
        )

        for counts in [[:], [token.placeholder: 2]] {
            XCTAssertThrowsError(
                try MarkdownMathConsumptionValidator.validate(
                    tokens: [token],
                    consumedPlaceholders: counts
                )
            ) { error in
                XCTAssertEqual(
                    error as? MarkdownMathConversionError,
                    .formulaPlacementMismatch(line: 7, column: 9)
                )
            }
        }
        XCTAssertNoThrow(
            try MarkdownMathConsumptionValidator.validate(
                tokens: [token],
                consumedPlaceholders: [token.placeholder: 1]
            )
        )
    }

    func testCommonMarkDestinationAndReferenceMetadataRemainLiteral() throws {
        let sources = [
            "Use [ref].\n\n[\nref\n]: https://example.com/$x$",
            "[link](<https://example.com/a)$x$>)",
            "[ref]: https://example.com\n\"$x$\"",
        ]

        for source in sources {
            let result = try MarkdownMathScanner().scan(source)
            XCTAssertTrue(result.tokens.isEmpty, "Source: \(source)")
            XCTAssertEqual(result.markdown, source)
        }
    }

    func testVisibleInvalidReferenceLikeTextRemainsEligible() throws {
        let sources = [
            "[ref]: invalid destination $x$",
            "Use [ref].\n\n[ref]: https://example.com\n\"$x$\" ok",
        ]

        for source in sources {
            let result = try MarkdownMathScanner().scan(source)
            XCTAssertEqual(result.tokens.count, 1, "Source: \(source)")
            XCTAssertEqual(result.tokens.first?.latex, "x", "Source: \(source)")
        }
    }

    func testInvalidReferenceTitleRecoveryNeverConsumesMatchingDestinationFormula() throws {
        let source = "Use [ref].\n\n[ref]: https://example.com/$x$\n\"$x$\" ok"
        let result = try MarkdownMathScanner().scan(source)

        XCTAssertEqual(result.tokens.map(\.latex), ["x"])
        XCTAssertTrue(result.markdown.contains("https://example.com/$x$"))
        XCTAssertEqual(
            result.markdown.components(separatedBy: MarkdownMathScanner.defaultMarkerPrefix).count - 1,
            1
        )
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
