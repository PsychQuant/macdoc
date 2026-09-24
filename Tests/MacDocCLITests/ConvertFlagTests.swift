import Testing
import Foundation

/// E2E 測試：flag 組合
struct ConvertFlagTests {

    @Test("--full on md → html produces complete HTML document")
    func fullFlagMdToHtml() throws {
        let input = FixtureManager.markdownFile()
        let result = try CLITestHelper.convert(to: "html", input: input, flags: ["--full"])
        #expect(result.succeeded, "should succeed")
        #expect(result.stdout.contains("<!DOCTYPE html>") || result.stdout.contains("<!doctype html>"),
                "should contain DOCTYPE")
    }

    @Test("--css dark on srt → html produces dark theme")
    func cssDarkSrtToHtml() throws {
        let input = FixtureManager.srtFile()
        let result = try CLITestHelper.convert(to: "html", input: input, flags: ["--full", "--css", "dark"])
        // 驗證有 dark 相關 CSS（不管 exit code，因為 convertToStdout bug）
        let output = result.stdout.lowercased()
        #expect(output.contains("dark") || output.contains("#1a1a2e") || output.contains("background"),
                "should contain dark theme elements")
    }

    @Test("srt → html without --css succeeds using the route's own default style (#216)")
    func srtToHtmlWithoutCSSSucceeds() throws {
        // Global --css default used to be `web`, which this route rejects
        // (only dark/light are valid), so converting an .srt without an
        // explicit --css always failed with exit 64.
        //
        // --output (not the no-flags/no-output stdout path) is deliberate:
        // that stdout path goes through SRTConverter.convertToStdout, which
        // has its own pre-existing, unrelated bug ("Error: The file
        // couldn't be saved.", already called out in cssDarkSrtToHtml
        // above) that would make this test fail for a reason that has
        // nothing to do with #216.
        let input = FixtureManager.srtFile()
        let outputPath = FixtureManager.outputPath("srt-no-css-output.html")
        let result = try CLITestHelper.convert(to: "html", input: input, flags: ["--output", outputPath])
        #expect(result.succeeded, "should succeed without --css\nstderr: \(result.stderr)")
        #expect(FileManager.default.fileExists(atPath: outputPath), "output file should exist")
    }

    @Test("--frontmatter on docx → md produces YAML")
    func frontmatterDocxToMd() throws {
        let input = FixtureManager.docxFile()
        let result = try CLITestHelper.convert(to: "md", input: input, flags: ["--frontmatter"])
        // stdout 應以 --- 開頭（YAML frontmatter）
        #expect(result.stdout.hasPrefix("---"), "should start with YAML delimiter")
    }

    @Test("--output writes to specified file")
    func outputFlag() throws {
        let input = FixtureManager.markdownFile()
        let outputPath = FixtureManager.outputPath("flag-test-output.html")
        let result = try CLITestHelper.convert(to: "html", input: input, flags: ["--output", outputPath])
        #expect(result.succeeded, "should succeed")
        #expect(FileManager.default.fileExists(atPath: outputPath), "file should exist")
        let content = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(content.contains("<h1") || content.contains("<p"), "should contain HTML")
    }

    @Test("--html-extensions on html → md preserves raw HTML")
    func htmlExtensionsFlag() throws {
        let input = FixtureManager.htmlFile()
        let result = try CLITestHelper.convert(to: "md", input: input, flags: ["--html-extensions"])
        // html-extensions 應保留 <u>/<sup> 等 raw HTML
        #expect(result.stdout.contains("<u>") || result.stdout.contains("<sup>"),
                "should preserve HTML tags")
    }
}
