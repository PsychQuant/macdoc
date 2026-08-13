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
