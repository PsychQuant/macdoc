#if canImport(XCTest)
import Foundation
import XCTest
import MDToWord
import CommonConverterSwift

final class MarkdownOMathConversionTests: XCTestCase {
    func testPublicClientCanConstructOMathConverter() {
        let converter = MarkdownToWordConverter(mathMode: .omath)
        _ = converter
    }

    func testDefaultConverterPreservesDollarDelimitedText() throws {
        let xml = try documentXML(
            markdown: "Before $x^2$ after",
            converter: MarkdownToWordConverter()
        )

        XCTAssertTrue(xml.contains("Before $x^2$ after"), "Got: \(xml)")
        XCTAssertFalse(xml.contains("<m:oMath"), "Got: \(xml)")
    }

    func testExplicitLiteralModeMatchesDefaultBehavior() throws {
        let source = "Before $x^2$ after"
        let defaultXML = try documentXML(
            markdown: source,
            converter: MarkdownToWordConverter()
        )
        let literalXML = try documentXML(
            markdown: source,
            converter: MarkdownToWordConverter(mathMode: .literal)
        )

        XCTAssertTrue(defaultXML.contains("Before $x^2$ after"), "Got: \(defaultXML)")
        XCTAssertTrue(literalXML.contains("Before $x^2$ after"), "Got: \(literalXML)")
        XCTAssertFalse(defaultXML.contains("<m:oMath"), "Got: \(defaultXML)")
        XCTAssertFalse(literalXML.contains("<m:oMath"), "Got: \(literalXML)")
    }

    func testSupportedFractionUsesNativeInlineOMath() throws {
        let xml = try documentXML(
            markdown: #"$\frac{a}{b}$"#,
            converter: MarkdownToWordConverter(mathMode: .omath)
        )

        XCTAssertEqual(count("<m:oMath>", in: xml), 1, "Got: \(xml)")
        XCTAssertEqual(count("<m:f>", in: xml), 1, "Got: \(xml)")
        XCTAssertTrue(xml.contains("<m:num>"), "Got: \(xml)")
        XCTAssertTrue(xml.contains("<m:den>"), "Got: \(xml)")
        XCTAssertFalse(xml.contains(#"$\frac{a}{b}$"#), "Got: \(xml)")
    }

    func testInlineOMathIsDirectParagraphChildInSourceOrder() throws {
        let xml = try documentXML(
            markdown: "Before $x^2$ after",
            converter: MarkdownToWordConverter(mathMode: .omath)
        )

        let before = try XCTUnwrap(xml.range(of: "Before ")?.lowerBound)
        let math = try XCTUnwrap(xml.range(of: "<m:oMath>")?.lowerBound)
        let after = try XCTUnwrap(xml.range(of: " after")?.lowerBound)
        XCTAssertLessThan(before, math)
        XCTAssertLessThan(math, after)
        XCTAssertEqual(count("<m:oMath>", in: xml), 1, "Got: \(xml)")
        XCTAssertFalse(xml.contains("<w:r><m:oMath>"), "Got: \(xml)")
        XCTAssertFalse(xml.contains("$x^2$"), "Got: \(xml)")
    }

    func testDecodedCallerTextCannotCollideWithMathPlaceholder() throws {
        let xml = try documentXML(
            markdown: "Keep MDTOWORDMATHPLACEHOLDER&#48;TOKEN and $x$",
            converter: MarkdownToWordConverter(mathMode: .omath)
        )

        XCTAssertTrue(xml.contains("MDTOWORDMATHPLACEHOLDER0TOKEN"), "Got: \(xml)")
        XCTAssertEqual(count("<m:oMath>", in: xml), 1, "Got: \(xml)")
    }

    func testInlineMathInLinkLabelPreservesMathAndDestination() throws {
        let markdown = "See [$x$](https://example.com/math)"
        let converter = MarkdownToWordConverter(mathMode: .omath)
        let xml = try documentXML(markdown: markdown, converter: converter)
        let document = try converter.convertMarkdown(markdown)

        XCTAssertEqual(count("<m:oMath>", in: xml), 1, "Got: \(xml)")
        XCTAssertFalse(xml.contains("MDTOWORDMATHPLACEHOLDER"), "Got: \(xml)")
        XCTAssertTrue(xml.contains("<w:hyperlink"), "Got: \(xml)")
        XCTAssertTrue(xml.contains("<m:t>x</m:t>"), "Got: \(xml)")
        XCTAssertEqual(document.hyperlinkReferences.first?.url, "https://example.com/math")
    }

    func testInlineMathInImageAltTextDoesNotLeakPlaceholder() throws {
        let xml = try documentXML(
            markdown: "![Plot $x$](missing.png)",
            converter: MarkdownToWordConverter(mathMode: .omath)
        )

        XCTAssertEqual(count("<m:oMath>", in: xml), 1, "Got: \(xml)")
        XCTAssertFalse(xml.contains("MDTOWORDMATHPLACEHOLDER"), "Got: \(xml)")
        XCTAssertTrue(xml.contains("Plot "), "Got: \(xml)")
    }

    func testDisplayFormulaUsesOMathParaWithoutSyntheticTextRun() throws {
        let xml = try documentXML(
            markdown: #"$$\frac{a}{b}$$"#,
            converter: MarkdownToWordConverter(mathMode: .omath)
        )

        XCTAssertEqual(count("<m:oMathPara>", in: xml), 1, "Got: \(xml)")
        XCTAssertEqual(count("<m:oMath>", in: xml), 1, "Got: \(xml)")
        XCTAssertTrue(xml.contains("<m:oMathPara><m:oMath>"), "Got: \(xml)")
        XCTAssertFalse(xml.contains(#"$$\frac{a}{b}$$"#), "Got: \(xml)")

        let mathParagraphStart = try XCTUnwrap(xml.range(of: "<m:oMathPara>")?.lowerBound)
        let paragraphEnd = try XCTUnwrap(xml.range(of: "</w:p>", range: mathParagraphStart..<xml.endIndex)?.lowerBound)
        let mathParagraphXML = String(xml[mathParagraphStart..<paragraphEnd])
        XCTAssertFalse(mathParagraphXML.contains("<w:t"), "Got: \(mathParagraphXML)")
    }

    func testStreamingXMLDeclaresMathNamespaceAndParses() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("markdown-omath-stream-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("fixture.md")
        try "Before $x$ after".write(to: input, atomically: true, encoding: .utf8)
        var output = StringOutput()
        try MarkdownToWordConverter(mathMode: .omath).convert(
            input: input,
            output: &output,
            options: .default
        )

        XCTAssertTrue(
            output.content.contains(
                "xmlns:m=\"http://schemas.openxmlformats.org/officeDocument/2006/math\""
            ),
            "Got: \(output.content)"
        )
        XCTAssertEqual(count("<m:oMath>", in: output.content), 1)
        XCTAssertNoThrow(
            try XMLDocument(
                data: Data(output.content.utf8),
                options: [.nodePreserveAll]
            )
        )
    }

    func testArchivedOMathDeclaresMathNamespaceAndParses() throws {
        let xml = try documentXML(
            markdown: "Before $x$ after",
            converter: MarkdownToWordConverter(mathMode: .omath)
        )

        XCTAssertTrue(
            xml.contains(
                "xmlns:m=\"http://schemas.openxmlformats.org/officeDocument/2006/math\""
            ),
            "Got: \(xml)"
        )
        XCTAssertNoThrow(
            try XMLDocument(
                data: Data(xml.utf8),
                options: [.nodePreserveAll]
            )
        )
    }

    func testReferenceDefinitionContinuationPreservesRelationshipTarget() throws {
        let markdown = "[link][ref]\n\n[ref]:\n  https://example.com/$x$"
        let document = try MarkdownToWordConverter(mathMode: .omath)
            .convertMarkdown(markdown)

        XCTAssertEqual(
            document.hyperlinkReferences.first?.url,
            "https://example.com/$x$"
        )
    }

    func testMultilineInlineLinkDestinationPreservesRelationshipTarget() throws {
        let markdown = "[link](\nhttps://example.com/$x$\n)"
        let converter = MarkdownToWordConverter(mathMode: .omath)
        let document = try converter.convertMarkdown(markdown)
        let xml = try documentXML(markdown: markdown, converter: converter)

        XCTAssertEqual(
            document.hyperlinkReferences.first?.url,
            "https://example.com/$x$"
        )
        XCTAssertFalse(xml.contains("MDTOWORDMATHPLACEHOLDER"), "Got: \(xml)")
        XCTAssertFalse(xml.contains("<m:oMath"), "Got: \(xml)")
    }

    func testReferenceDefinitionOptionalTitleDoesNotBecomeMath() throws {
        let sources = [
            "Use [reference][ref].\n\n[ref]: https://example.com\n\"$x$\"",
            "Use [reference][ref].\n\n[ref]: https://example.com\n\"$\\overbrace{x}$\"",
        ]

        for source in sources {
            let converter = MarkdownToWordConverter(mathMode: .omath)
            let document = try converter.convertMarkdown(source)
            let xml = try documentXML(markdown: source, converter: converter)

            XCTAssertEqual(document.hyperlinkReferences.first?.url, "https://example.com")
            XCTAssertFalse(xml.contains("MDTOWORDMATHPLACEHOLDER"), "Source: \(source)")
            XCTAssertFalse(xml.contains("<m:oMath"), "Source: \(source)")
        }
    }

    func testDisplayPlacementUsesCommonMarkParagraphBoundaries() throws {
        let rejected = [
            "Before\n$$x$$\nAfter",
            "Before\n$$\nx\n$$\nAfter",
            "$$\n\nx\n\n$$",
            "- $$\n- x\n- $$",
            "> $$\nx\n$$",
        ]
        for (index, source) in rejected.enumerated() {
            XCTAssertThrowsError(
                try MarkdownToWordConverter(mathMode: .omath).convertMarkdown(source)
            ) { error in
                let expectedColumn = index >= 3 ? 3 : 1
                let expectedLine = index < 2 ? 2 : 1
                XCTAssertEqual(
                    error as? MarkdownMathConversionError,
                    .misplacedDisplayFormula(line: expectedLine, column: expectedColumn),
                    "Source: \(source)"
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
            let xml = try documentXML(
                markdown: source,
                converter: MarkdownToWordConverter(mathMode: .omath)
            )
            XCTAssertEqual(count("<m:oMathPara>", in: xml), 1, "Source: \(source)")
            XCTAssertFalse(xml.contains("MDTOWORDMATHPLACEHOLDER"), "Source: \(source)")
        }
    }

    func testComplexCommonMarkDestinationsNeverReceivePlaceholders() throws {
        let cases: [(source: String, target: String)] = [
            (
                "Use [ref].\n\n[\nref\n]: https://example.com/$x$",
                "https://example.com/$x$"
            ),
            (
                "[link](<https://example.com/a)$x$>)",
                "https://example.com/a)$x$"
            ),
        ]

        for testCase in cases {
            let converter = MarkdownToWordConverter(mathMode: .omath)
            let document = try converter.convertMarkdown(testCase.source)
            let xml = try documentXML(markdown: testCase.source, converter: converter)

            XCTAssertEqual(document.hyperlinkReferences.first?.url, testCase.target)
            XCTAssertFalse(xml.contains("MDTOWORDMATHPLACEHOLDER"), "Source: \(testCase.source)")
            XCTAssertFalse(xml.contains("<m:oMath"), "Source: \(testCase.source)")
        }
    }

    func testInvalidHTMLLikeVisibleTextEmitsInlineMath() throws {
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
            let xml = try documentXML(
                markdown: source,
                converter: MarkdownToWordConverter(mathMode: .omath)
            )

            XCTAssertEqual(count("<m:oMath>", in: xml), 1, "Source: \(source)")
            XCTAssertTrue(xml.contains("&lt;"), "Source: \(source); got: \(xml)")
            XCTAssertFalse(
                xml.contains("MDTOWORDMATHPLACEHOLDER"),
                "Source: \(source); got: \(xml)"
            )
        }
    }

    func testInvalidReferenceLikeVisibleTextStillConvertsInlineMath() throws {
        let sources = [
            "[ref]: invalid destination $x$",
            "Use [ref].\n\n[ref]: https://example.com\n\"$x$\" ok",
        ]

        for source in sources {
            let xml = try documentXML(
                markdown: source,
                converter: MarkdownToWordConverter(mathMode: .omath)
            )
            XCTAssertEqual(count("<m:oMath>", in: xml), 1, "Source: \(source); XML: \(xml)")
            XCTAssertFalse(xml.contains("MDTOWORDMATHPLACEHOLDER"), "Source: \(source)")
        }
    }

    func testInvalidReferenceTitleConvertsVisibleMathWithoutChangingMatchingTarget() throws {
        let source = "Use [ref].\n\n[ref]: https://example.com/$x$\n\"$x$\" ok"
        let converter = MarkdownToWordConverter(mathMode: .omath)
        let document = try converter.convertMarkdown(source)
        let xml = try documentXML(markdown: source, converter: converter)

        XCTAssertEqual(document.hyperlinkReferences.first?.url, "https://example.com/$x$")
        XCTAssertEqual(count("<m:oMath>", in: xml), 1)
        XCTAssertFalse(xml.contains("MDTOWORDMATHPLACEHOLDER"))
    }

    func testHTMLAndFormattingNodeBoundariesNeverCreateMathTokens() throws {
        let sources = [
            "<!--\n$\\overbrace{x}$\n-->\nVisible",
            "<div>\n$\\overbrace{x}$\n</div>\nVisible",
            #"<span title="> $x$">text</span>"#,
            #"<span foo=? title="$x$">text</span>"#,
            "$*x*$",
            "$**x**$",
        ]

        for source in sources {
            let converter = MarkdownToWordConverter(mathMode: .omath)
            let document = try converter.convertMarkdown(source)
            let xml = try documentXML(markdown: source, converter: converter)

            XCTAssertNil(document.documentRootAttributes["xmlns:m"], "Source: \(source)")
            XCTAssertFalse(xml.contains("<m:oMath"), "Source: \(source); XML: \(xml)")
            XCTAssertFalse(xml.contains("MDTOWORDMATHPLACEHOLDER"), "Source: \(source); XML: \(xml)")
        }
    }

    func testCodeBlocksNeverLeakGeneratedPlaceholders() throws {
        let sources = [
            "> ~~~text\n> $x$\n> ~~~",
            "- ~~~text\n  $x$\n  ~~~",
            "    $x$",
        ]

        for source in sources {
            let xml = try documentXML(
                markdown: source,
                converter: MarkdownToWordConverter(mathMode: .omath)
            )
            XCTAssertTrue(xml.contains("$x$"), "Source: \(source); XML: \(xml)")
            XCTAssertFalse(
                xml.contains("MDTOWORDMATHPLACEHOLDER"),
                "Source: \(source); XML: \(xml)"
            )
            XCTAssertFalse(xml.contains("<m:oMath"), "Source: \(source); XML: \(xml)")
        }
    }

    func testDenseInlineMathConversionDoesNotRescanEveryToken() throws {
        let source = Array(repeating: "$x$", count: 400).joined(separator: " ")
        let started = Date()
        let document = try MarkdownToWordConverter(mathMode: .omath)
            .convertMarkdown(source)
        let elapsed = Date().timeIntervalSince(started)
        let xml = document.getAllParagraphs().map { $0.toXML() }.joined()

        XCTAssertEqual(count("<m:oMath>", in: xml), 400)
        XCTAssertLessThan(
            elapsed,
            5,
            "Dense inline conversion took \(elapsed) seconds"
        )
    }

    func testUnsupportedFormulaIsNormalizedWithSourceLocation() {
        XCTAssertThrowsError(
            try MarkdownToWordConverter(mathMode: .omath)
                .convertMarkdown("First\n\n  $\\overbrace{x}$")
        ) { error in
            XCTAssertEqual(
                error as? MarkdownMathConversionError,
                .unsupportedFormula(token: #"\overbrace"#, line: 3, column: 3)
            )
        }
    }

    func testUnsupportedFormulaColumnUsesCommonMarkUTF8Semantics() {
        XCTAssertThrowsError(
            try MarkdownToWordConverter(mathMode: .omath).convertMarkdown(
                "你$\\overbrace{x}$"
            )
        ) { error in
            XCTAssertEqual(
                error as? MarkdownMathConversionError,
                .unsupportedFormula(token: "\\overbrace", line: 1, column: 4)
            )
        }
    }

    func testFormulaLocationIncludesFrontmatterLines() {
        let markdown = """
        ---
        title: Math
        ---
        $\\overbrace{x}$
        """

        XCTAssertThrowsError(
            try MarkdownToWordConverter(mathMode: .omath).convertMarkdown(markdown)
        ) { error in
            XCTAssertEqual(
                error as? MarkdownMathConversionError,
                .unsupportedFormula(token: #"\overbrace"#, line: 4, column: 1)
            )
        }
    }

    func testMalformedFormulaIsNormalizedWithSourceLocation() {
        XCTAssertThrowsError(
            try MarkdownToWordConverter(mathMode: .omath)
                .convertMarkdown(#"before $\frac{a}{b$"#)
        ) { error in
            XCTAssertEqual(
                error as? MarkdownMathConversionError,
                .malformedFormula(line: 1, column: 8)
            )
        }
    }

    func testMisplacedDisplayFormulaIsNormalizedWithSourceLocation() {
        XCTAssertThrowsError(
            try MarkdownToWordConverter(mathMode: .omath)
                .convertMarkdown("before $$x$$ after")
        ) { error in
            XCTAssertEqual(
                error as? MarkdownMathConversionError,
                .misplacedDisplayFormula(line: 1, column: 8)
            )
        }
    }

    func testUnsupportedFormulaLeavesAbsentDestinationAbsent() throws {
        let directory = try makeWorkspace(prefix: "markdown-omath-absent-output")
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("fixture.md")
        let output = directory.appendingPathComponent("fixture.docx")
        try #"$\overbrace{x}$"#.write(to: input, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try MarkdownToWordConverter(mathMode: .omath)
                .convertToFile(input: input, output: output)
        ) { error in
            XCTAssertEqual(
                error as? MarkdownMathConversionError,
                .unsupportedFormula(token: #"\overbrace"#, line: 1, column: 1)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testMalformedFormulaPreservesExistingDestination() throws {
        let directory = try makeWorkspace(prefix: "markdown-omath-existing-output")
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("fixture.md")
        let output = directory.appendingPathComponent("fixture.docx")
        let sentinel = Data("KEEP".utf8)
        try #"$\frac{a}{b$"#.write(to: input, atomically: true, encoding: .utf8)
        try sentinel.write(to: output)

        XCTAssertThrowsError(
            try MarkdownToWordConverter(mathMode: .omath)
                .convertToFile(input: input, output: output)
        ) { error in
            XCTAssertEqual(
                error as? MarkdownMathConversionError,
                .malformedFormula(line: 1, column: 1)
            )
        }
        XCTAssertEqual(try Data(contentsOf: output), sentinel)
    }

    private func documentXML(
        markdown: String,
        converter: MarkdownToWordConverter
    ) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("markdown-omath-mode-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("fixture.md")
        let output = directory.appendingPathComponent("fixture.docx")
        try markdown.write(to: input, atomically: true, encoding: .utf8)
        try converter.convertToFile(input: input, output: output)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", output.path, "word/document.xml"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            XCTFail("Failed to read document.xml: \(String(decoding: errorData, as: UTF8.self))")
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func makeWorkspace(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func count(_ needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}
#endif
