import Testing
import Foundation

/// E2E 測試：所有 convert 路由
struct ConvertRouteTests {

    /// 驗證 stdout 包含預期內容，並檢查 exit code。
    ///
    /// PsychQuant/macdoc#223：這裡曾經只驗證內容、不驗證 exit code，因為
    /// `common-converter-swift` 的 `convertToStdout` 路由（`docx → md`、
    /// `docx → html`、`html → md`、`srt → html` 都走這條）在 stdout 是 pipe
    /// 時——而 `CLITestHelper.run` 底下正是用 `Pipe()` 接 stdout——即使內容
    /// 完全正確也會以 exit 1 結束。那個 bug 已在 common-converter-swift
    /// 修好（`FileHandleOutput.flush()` 不再對 pipe 做 fsync），這裡改回
    /// 檢查 exit code，不然這個測試本身就是 bug 被掩蓋掉的原因。
    func assertOutputContains(_ result: CLIResult, _ substring: String, message: String) {
        #expect(result.succeeded, "\(message) — exit code 應為 0\nstderr: \(result.stderr)")
        #expect(result.stdout.contains(substring), "\(message). stdout was: \(result.stdout.prefix(200))")
    }

    // MARK: - Text Output Routes (Group 2)

    @Test("docx → md")
    func docxToMd() throws {
        let input = FixtureManager.docxFile()
        let result = try CLITestHelper.convert(to: "md", input: input)
        assertOutputContains(result, "Test Heading", message: "should contain document text")
    }

    @Test("docx → html")
    func docxToHtml() throws {
        let input = FixtureManager.docxFile()
        let result = try CLITestHelper.convert(to: "html", input: input)
        assertOutputContains(result, "<h1", message: "should contain HTML heading")
    }

    @Test("html → md")
    func htmlToMd() throws {
        let input = FixtureManager.htmlFile()
        let result = try CLITestHelper.convert(to: "md", input: input)
        assertOutputContains(result, "Test Document", message: "should contain heading text")
    }

    @Test("md → html")
    func mdToHtml() throws {
        let input = FixtureManager.markdownFile()
        let result = try CLITestHelper.convert(to: "html", input: input)
        #expect(result.succeeded, "md → html should succeed")
        assertOutputContains(result, "<h1", message: "should contain HTML heading")
    }

    @Test("srt → html")
    func srtToHtml() throws {
        let input = FixtureManager.srtFile()
        let result = try CLITestHelper.convert(to: "html", input: input, flags: ["--css", "dark"])
        assertOutputContains(result, "speaker", message: "should contain speaker class")
    }

    @Test("bib → html")
    func bibToHtml() throws {
        let input = FixtureManager.bibFile()
        let result = try CLITestHelper.convert(to: "html", input: input)
        #expect(result.succeeded, "bib → html should succeed")
        assertOutputContains(result, "Smith", message: "should contain author")
    }

    @Test("bib → md")
    func bibToMd() throws {
        let input = FixtureManager.bibFile()
        let result = try CLITestHelper.convert(to: "md", input: input)
        #expect(result.succeeded, "bib → md should succeed")
        assertOutputContains(result, "Smith", message: "should contain author")
    }

    @Test("bib → json")
    func bibToJson() throws {
        let input = FixtureManager.bibFile()
        let result = try CLITestHelper.convert(to: "json", input: input)
        #expect(result.succeeded, "bib → json should succeed")
        assertOutputContains(result, "{", message: "should contain JSON")
    }

    @Test("pdf → md")
    func pdfToMd() throws {
        let input = FixtureManager.pdfFile()
        let result = try CLITestHelper.convert(to: "md", input: input)
        // PDF 提取完成不 crash 就好
        #expect(!result.stdout.isEmpty || result.succeeded, "should produce output or succeed")
    }

    @Test("html → pdf")
    func htmlToPdf() throws {
        let input = FixtureManager.htmlFile()
        let outputPath = FixtureManager.outputPath("output-html.pdf")
        let result = try CLITestHelper.convert(to: "pdf", input: input, flags: ["--output", outputPath])
        if result.stderr.contains("playwright") && !result.succeeded {
            return  // playwright 未安裝，跳過
        }
        #expect(result.succeeded, "html → pdf should succeed")
        #expect(FileManager.default.fileExists(atPath: outputPath), "output file should exist")
    }

    // MARK: - Binary Output Routes (Group 3)

    @Test("html → docx")
    func htmlToDocx() throws {
        let input = FixtureManager.htmlFile()
        let outputPath = FixtureManager.outputPath("output-html.docx")
        let result = try CLITestHelper.convert(to: "docx", input: input, flags: ["--output", outputPath])
        #expect(result.succeeded, "html → docx should succeed")
        #expect(FileManager.default.fileExists(atPath: outputPath), "output file should exist")
        let size = (try? FileManager.default.attributesOfItem(atPath: outputPath)[.size] as? Int) ?? 0
        #expect(size > 0, "output file should be non-empty")
    }

    @Test("md → docx")
    func mdToDocx() throws {
        let input = FixtureManager.markdownFile()
        let outputPath = FixtureManager.outputPath("output-md.docx")
        let result = try CLITestHelper.convert(to: "docx", input: input, flags: ["--output", outputPath])
        #expect(result.succeeded, "md → docx should succeed")
        #expect(FileManager.default.fileExists(atPath: outputPath), "output file should exist")
    }

    @Test("pdf → docx")
    func pdfToDocx() throws {
        let input = FixtureManager.pdfFile()
        let outputPath = FixtureManager.outputPath("output-pdf.docx")
        let result = try CLITestHelper.convert(to: "docx", input: input, flags: ["--output", outputPath])
        #expect(result.succeeded, "pdf → docx should succeed")
        #expect(FileManager.default.fileExists(atPath: outputPath), "output file should exist")
    }

    @Test("tex → docx")
    func texToDocx() throws {
        let input = FixtureManager.texFile()
        let outputPath = FixtureManager.outputPath("output-tex.docx")
        let result = try CLITestHelper.convert(to: "docx", input: input, flags: ["--output", outputPath])
        #expect(result.succeeded, "tex → docx should succeed")
        #expect(FileManager.default.fileExists(atPath: outputPath), "output file should exist")
    }

    // MARK: - #223: stdout as a real OS pipe

    /// Literal reproduction of #223's repro line
    /// (`macdoc convert --to html a.srt | cat`): a *real* shell pipeline
    /// with macdoc's stdout connected to another process's stdin, not just
    /// `CLITestHelper`'s own `Pipe()`-backed capture (every other test in
    /// this file already runs through that pipe — restoring the exit-code
    /// checks above is itself a regression test — but this one pins the
    /// exact user-facing scenario the issue reported, independent of how
    /// `CLITestHelper` happens to capture output). `set -o pipefail` makes
    /// the shell's own exit code reflect macdoc's, not `cat`'s.
    @Test("stdout piped through another process exits 0 (macdoc#223)")
    func stdoutThroughARealPipeExitsZero() throws {
        let binary = try CLITestHelper.binaryPath
        let input = FixtureManager.srtFile()
        let shellCommand = "set -o pipefail; '\(binary)' convert --to html --css dark '\(input)' | cat > /dev/null"
        let result = try CLITestHelper.runProcess(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", shellCommand],
            currentDirectory: CLITestHelper.repoRoot,
            timeout: 30)
        #expect(result.succeeded,
                "macdoc convert piped to another process should exit 0, not fail with \"couldn't be saved\"\nstderr: \(result.stderr)")
    }
}
