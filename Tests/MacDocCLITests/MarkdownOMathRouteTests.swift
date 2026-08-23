import Foundation
import Testing

struct MarkdownOMathRouteTests {
    @Test("md to docx defaults to literal dollar text")
    func defaultModeIsLiteral() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let input = workspace.appendingPathComponent("fixture.md")
        let output = workspace.appendingPathComponent("fixture.docx")
        try "Before $x^2$ after".write(to: input, atomically: true, encoding: .utf8)

        let result = try CLITestHelper.convert(
            to: "docx",
            input: input.path,
            flags: ["--output", output.path]
        )

        #expect(result.succeeded, "stderr: \(result.stderr)")
        let xml = try archiveEntry(named: "word/document.xml", in: output)
        #expect(xml.contains("Before $x^2$ after"))
        #expect(!xml.contains("<m:oMath>"))
    }

    @Test("explicit literal mode preserves dollar text")
    func explicitLiteralMode() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let input = workspace.appendingPathComponent("fixture.markdown")
        let output = workspace.appendingPathComponent("fixture.docx")
        try "$x$".write(to: input, atomically: true, encoding: .utf8)

        let result = try CLITestHelper.convert(
            to: "docx",
            input: input.path,
            flags: ["--math", "literal", "--output", output.path]
        )

        #expect(result.succeeded, "stderr: \(result.stderr)")
        let xml = try archiveEntry(named: "word/document.xml", in: output)
        #expect(xml.contains("$x$"))
        #expect(!xml.contains("<m:oMath>"))
    }

    @Test("omath mode emits inline native Word math")
    func inlineOMathMode() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let input = workspace.appendingPathComponent("fixture.md")
        let output = workspace.appendingPathComponent("fixture.docx")
        try "Before $x^2$ after".write(to: input, atomically: true, encoding: .utf8)

        let result = try CLITestHelper.convert(
            to: "docx",
            input: input.path,
            flags: ["--math", "omath", "--output", output.path]
        )

        #expect(result.succeeded, "stderr: \(result.stderr)")
        #expect(result.stdout.isEmpty)
        let xml = try archiveEntry(named: "word/document.xml", in: output)
        #expect(xml.components(separatedBy: "<m:oMath>").count - 1 == 1)
        #expect(!xml.contains("$x^2$"))
        #expect(
            xml.contains(
                "xmlns:m=\"http://schemas.openxmlformats.org/officeDocument/2006/math\""
            )
        )
        _ = try XMLDocument(data: Data(xml.utf8), options: [.nodePreserveAll])
    }

    @Test("omath mode emits display native Word math")
    func displayOMathMode() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let input = workspace.appendingPathComponent("fixture.md")
        let output = workspace.appendingPathComponent("fixture.docx")
        try #"$$\frac{a}{b}$$"#.write(to: input, atomically: true, encoding: .utf8)

        let result = try CLITestHelper.convert(
            to: "docx",
            input: input.path,
            flags: ["--math", "omath", "--output", output.path]
        )

        #expect(result.succeeded, "stderr: \(result.stderr)")
        let xml = try archiveEntry(named: "word/document.xml", in: output)
        #expect(xml.components(separatedBy: "<m:oMathPara>").count - 1 == 1)
        #expect(xml.components(separatedBy: "<m:oMath>").count - 1 == 1)
    }

    @Test("unmatched display delimiter does not consume a later complete display")
    func unmatchedThenCompleteDisplay() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let input = workspace.appendingPathComponent("fixture.md")
        let output = workspace.appendingPathComponent("fixture.docx")
        try "Unmatched $$ here\n\n$$x$$\n".write(
            to: input,
            atomically: true,
            encoding: .utf8
        )

        let result = try CLITestHelper.convert(
            to: "docx",
            input: input.path,
            flags: ["--math", "omath", "--output", output.path]
        )

        #expect(result.succeeded, "stderr: \(result.stderr)")
        let xml = try archiveEntry(named: "word/document.xml", in: output)
        #expect(xml.contains("Unmatched $$ here"))
        #expect(xml.components(separatedBy: "<m:oMathPara>").count - 1 == 1)
        #expect(!xml.contains("MDTOWORDMATHPLACEHOLDER"))
    }

    @Test("invalid math value fails before replacing destination")
    func invalidMathValuePreservesDestination() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let input = workspace.appendingPathComponent("fixture.md")
        let output = workspace.appendingPathComponent("fixture.docx")
        let sentinel = Data("KEEP".utf8)
        try "$x$".write(to: input, atomically: true, encoding: .utf8)
        try sentinel.write(to: output)

        let result = try CLITestHelper.convert(
            to: "docx",
            input: input.path,
            flags: ["--math", "unknown", "--output", output.path]
        )

        #expect(!result.succeeded)
        #expect(result.stdout.isEmpty)
        #expect(try Data(contentsOf: output) == sentinel)
    }

    @Test("omath is rejected outside the Markdown to docx route")
    func incompatibleRoutePreservesDestination() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let input = workspace.appendingPathComponent("fixture.md")
        let output = workspace.appendingPathComponent("fixture.html")
        let sentinel = Data("KEEP".utf8)
        try "$x$".write(to: input, atomically: true, encoding: .utf8)
        try sentinel.write(to: output)

        let result = try CLITestHelper.convert(
            to: "html",
            input: input.path,
            flags: ["--math", "omath", "--output", output.path]
        )

        #expect(!result.succeeded)
        #expect(result.stdout.isEmpty)
        #expect(try Data(contentsOf: output) == sentinel)
    }

    @Test("formula error fails before replacing destination")
    func formulaErrorPreservesDestination() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let input = workspace.appendingPathComponent("fixture.md")
        let output = workspace.appendingPathComponent("fixture.docx")
        let sentinel = Data("KEEP".utf8)
        try #"$\overbrace{x}$"#.write(to: input, atomically: true, encoding: .utf8)
        try sentinel.write(to: output)

        let result = try CLITestHelper.convert(
            to: "docx",
            input: input.path,
            flags: ["--math", "omath", "--output", output.path]
        )

        #expect(!result.succeeded)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("line 1, column 1"))
        #expect(try Data(contentsOf: output) == sentinel)
    }

    @Test("display math sharing a logical paragraph fails before replacing destination")
    func mixedLogicalParagraphDisplayPreservesDestination() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let input = workspace.appendingPathComponent("fixture.md")
        let output = workspace.appendingPathComponent("fixture.docx")
        let sentinel = Data("KEEP".utf8)
        try "Before\n$$x$$\nAfter".write(to: input, atomically: true, encoding: .utf8)
        try sentinel.write(to: output)

        let result = try CLITestHelper.convert(
            to: "docx",
            input: input.path,
            flags: ["--math", "omath", "--output", output.path]
        )

        #expect(!result.succeeded)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("line 2, column 1"))
        #expect(try Data(contentsOf: output) == sentinel)
    }

    @Test("multiline link destination remains byte-exact in relationship")
    func multilineLinkDestinationIsNotMath() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let input = workspace.appendingPathComponent("fixture.md")
        let output = workspace.appendingPathComponent("fixture.docx")
        try "[link](\nhttps://example.com/$x$\n)".write(
            to: input,
            atomically: true,
            encoding: .utf8
        )

        let result = try CLITestHelper.convert(
            to: "docx",
            input: input.path,
            flags: ["--math", "omath", "--output", output.path]
        )

        #expect(result.succeeded, "stderr: \(result.stderr)")
        let relationships = try archiveEntry(
            named: "word/_rels/document.xml.rels",
            in: output
        )
        #expect(relationships.contains("Target=\"https://example.com/$x$\""))
        #expect(!relationships.contains("MDTOWORDMATHPLACEHOLDER"))
    }

    @Test("standalone display next to other CommonMark blocks succeeds")
    func displayUsesParsedBlockBoundaries() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let input = workspace.appendingPathComponent("fixture.md")
        let output = workspace.appendingPathComponent("fixture.docx")
        try "# Heading\n$$x$$\n\nAfter".write(
            to: input,
            atomically: true,
            encoding: .utf8
        )

        let result = try CLITestHelper.convert(
            to: "docx",
            input: input.path,
            flags: ["--math", "omath", "--output", output.path]
        )

        #expect(result.succeeded, "stderr: \(result.stderr)")
        let xml = try archiveEntry(named: "word/document.xml", in: output)
        #expect(xml.components(separatedBy: "<m:oMathPara>").count - 1 == 1)
        #expect(!xml.contains("MDTOWORDMATHPLACEHOLDER"))
    }

    @Test("display math cannot cross original CommonMark blocks")
    func crossBlockDisplayPreservesDestination() throws {
        let sources = [
            "$$\n\nx\n\n$$",
            "- $$\n- x\n- $$",
            "> $$\nx\n$$",
        ]

        for source in sources {
            let workspace = try makeWorkspace()
            defer { try? FileManager.default.removeItem(at: workspace) }
            let input = workspace.appendingPathComponent("fixture.md")
            let output = workspace.appendingPathComponent("fixture.docx")
            let sentinel = Data("KEEP".utf8)
            try source.write(to: input, atomically: true, encoding: .utf8)
            try sentinel.write(to: output)

            let result = try CLITestHelper.convert(
                to: "docx",
                input: input.path,
                flags: ["--math", "omath", "--output", output.path]
            )

            #expect(!result.succeeded, "Source unexpectedly succeeded: \(source)")
            #expect(result.stdout.isEmpty)
            #expect(try Data(contentsOf: output) == sentinel)
        }
    }

    @Test("complex destinations remain byte-exact and placeholder-free")
    func complexDestinationsRemainLiteral() throws {
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
            let workspace = try makeWorkspace()
            defer { try? FileManager.default.removeItem(at: workspace) }
            let input = workspace.appendingPathComponent("fixture.md")
            let output = workspace.appendingPathComponent("fixture.docx")
            try testCase.source.write(to: input, atomically: true, encoding: .utf8)

            let result = try CLITestHelper.convert(
                to: "docx",
                input: input.path,
                flags: ["--math", "omath", "--output", output.path]
            )

            #expect(result.succeeded, "stderr: \(result.stderr)")
            let relationships = try archiveEntry(
                named: "word/_rels/document.xml.rels",
                in: output
            )
            let xml = try archiveEntry(named: "word/document.xml", in: output)
            #expect(relationships.contains("Target=\"\(testCase.target)\""))
            #expect(!relationships.contains("MDTOWORDMATHPLACEHOLDER"))
            #expect(!xml.contains("MDTOWORDMATHPLACEHOLDER"))
        }
    }

    @Test("HTML and formatting boundaries remain placeholder-free")
    func htmlAndFormattingBoundariesRemainLiteral() throws {
        let sources = [
            "<!--\n$\\overbrace{x}$\n-->\nVisible",
            #"<span title="> $x$">text</span>"#,
            #"<span foo=? title="$x$">text</span>"#,
            "$*x*$",
        ]

        for source in sources {
            let workspace = try makeWorkspace()
            defer { try? FileManager.default.removeItem(at: workspace) }
            let input = workspace.appendingPathComponent("fixture.md")
            let output = workspace.appendingPathComponent("fixture.docx")
            try source.write(to: input, atomically: true, encoding: .utf8)

            let result = try CLITestHelper.convert(
                to: "docx",
                input: input.path,
                flags: ["--math", "omath", "--output", output.path]
            )

            #expect(result.succeeded, "Source: \(source); stderr: \(result.stderr)")
            let xml = try archiveEntry(named: "word/document.xml", in: output)
            #expect(!xml.contains("MDTOWORDMATHPLACEHOLDER"))
            #expect(!xml.contains("<m:oMath"))
        }
    }

    @Test("invalid HTML-like visible text remains math eligible")
    func invalidHTMLLikeVisibleTextEmitsMath() throws {
        let sources = [
            "Visible <span $x$> tail",
            "Visible <$x$> tail",
            "Visible <span \"$x$\"> tail </span>",
            "Visible <span title=\"$x$\" ?> tail </span>",
            "Visible <span foo=bar=baz title=\"$x$\"> tail </span>",
            "Visible <span title=\"$x$\"foo=\"bar\"> tail </span>",
        ]
        for source in sources {
            let workspace = try makeWorkspace()
            defer { try? FileManager.default.removeItem(at: workspace) }
            let input = workspace.appendingPathComponent("fixture.md")
            let output = workspace.appendingPathComponent("fixture.docx")
            try source.write(to: input, atomically: true, encoding: .utf8)

            let result = try CLITestHelper.convert(
                to: "docx",
                input: input.path,
                flags: ["--math", "omath", "--output", output.path]
            )

            #expect(result.succeeded, "Source: \(source); stderr: \(result.stderr)")
            let xml = try archiveEntry(named: "word/document.xml", in: output)
            #expect(xml.components(separatedBy: "<m:oMath>").count - 1 == 1)
            #expect(xml.contains("&lt;"))
            #expect(!xml.contains("MDTOWORDMATHPLACEHOLDER"))
        }
    }

    private func makeWorkspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdoc-markdown-omath-cli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func archiveEntry(named path: String, in archiveURL: URL) throws -> String {
        let result = try CLITestHelper.runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-p", archiveURL.path, path],
            currentDirectory: nil,
            timeout: 10
        )
        guard result.succeeded else {
            throw ArchiveReadError(path: path, diagnostic: result.stderr)
        }
        return result.stdout
    }
}

private struct ArchiveReadError: Error {
    let path: String
    let diagnostic: String
}
