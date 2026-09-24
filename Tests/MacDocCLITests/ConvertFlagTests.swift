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
        // PsychQuant/macdoc#223：這個 route 帶 `--full`，走的是
        // writeStringOutput/print，本來就不受 convertToStdout 那個 fsync
        // bug 影響（見下面 srtToHtmlWithoutCSSSucceeds 的說明）；exit code
        // 之前沒檢查只是寫測試時過度保守，現在補回來。
        #expect(result.succeeded, "should succeed\nstderr: \(result.stderr)")
        let output = result.stdout.lowercased()
        #expect(output.contains("dark") || output.contains("#1a1a2e") || output.contains("background"),
                "should contain dark theme elements")
    }

    @Test("srt → html without --css succeeds and actually renders the dark theme (#216)")
    func srtToHtmlWithoutCSSSucceeds() throws {
        // Global --css default used to be `web`, which this route rejects
        // (only dark/light are valid), so converting an .srt without an
        // explicit --css always failed with exit 64.
        //
        // --full (not the no-flags/no-output stdout path) is deliberate:
        // the no-flags path goes through SRTConverter.convertToStdout,
        // which has its own pre-existing, unrelated bug ("Error: The file
        // couldn't be saved.", already called out in cssDarkSrtToHtml
        // above) that would make this test fail for a reason that has
        // nothing to do with #216. --full takes the writeStringOutput/print
        // path instead, which is unaffected by that bug and lets this
        // assert on the actual rendered content, not just "did it exit 0".
        let input = FixtureManager.srtFile()
        let result = try CLITestHelper.convert(to: "html", input: input, flags: ["--full"])
        #expect(result.succeeded, "should succeed without --css\nstderr: \(result.stderr)")
        // #0b1020 is SRTCSS.dark's body background — present only in the
        // dark theme, never in SRTCSS.light (#ffffff). A weaker check (e.g.
        // "contains 'dark'" or "contains 'background'") would pass even if
        // the fallback silently picked the wrong theme, or any theme at
        // all, since both stylesheets say "background" somewhere.
        #expect(result.stdout.contains("#0b1020"), "should render SRTCSS.dark, not some other/no style")
        #expect(!result.stdout.contains("#ffffff"), "should not also carry the light theme's background")
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

    @Test("bib → html without --css succeeds and actually renders the web style (#216)")
    func bibToHtmlWithoutCSSSucceeds() throws {
        // Bib → HTML's fallback (web) happens to match the old global
        // default, so this route never exhibited #216's exit-64 bug — but
        // now that the fallback is this route's own decision rather than an
        // ArgumentParser default, it deserves the same direct content check
        // as the srt/note routes above, not just "did it exit 0".
        let input = FixtureManager.bibFile()
        let result = try CLITestHelper.convert(to: "html", input: input, flags: ["--full"])
        #expect(result.succeeded, "should succeed without --css\nstderr: \(result.stderr)")
        // BlinkMacSystemFont is part of APACSS.web's font stack and does not
        // appear in APACSS.minimal ("Times New Roman", Times, serif).
        #expect(result.stdout.contains("BlinkMacSystemFont"), "should render APACSS.web, not minimal")
        #expect(!result.stdout.contains("Times New Roman"), "should not also carry the minimal theme's serif font")
    }

    @Test("--to tokens rejects an explicit --css even when it repeats the old global default")
    func tokensRouteRejectsExplicitCSS() throws {
        // #216 turned "was --css given at all" into a real, checkable
        // question (css: CSSStyle? with no default) instead of comparing
        // against the old global default `.web`. Confirm the tokens route,
        // which accepts no formatting options, still rejects --css even
        // when the value given is `web` — the one value that used to be
        // indistinguishable from "omitted".
        let input = FixtureManager.markdownFile()
        let result = try CLITestHelper.convert(to: "tokens", input: input, flags: ["--css", "web"])
        #expect(!result.succeeded, "should reject --css on the tokens route")
        #expect(result.stderr.contains("--css"), "error should name --css\nstderr: \(result.stderr)")
    }
}
