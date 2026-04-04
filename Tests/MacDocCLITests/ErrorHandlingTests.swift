import Testing
import Foundation

/// E2E 測試：錯誤處理
struct ErrorHandlingTests {

    @Test("Missing input file returns non-zero exit code")
    func missingInputFile() throws {
        let result = try CLITestHelper.convert(to: "md", input: "/nonexistent/path/file.docx")
        #expect(!result.succeeded, "should fail with non-zero exit code")
        let combined = result.stderr + result.stdout
        #expect(!combined.isEmpty, "should produce an error message")
    }

    @Test("Unsupported format pair returns non-zero exit code")
    func unsupportedFormatPair() throws {
        let input = FixtureManager.markdownFile()
        // md → pdf 不是支援的路由
        let result = try CLITestHelper.convert(to: "pdf", input: input)
        #expect(!result.succeeded, "unsupported route should fail")
    }

    @Test("Missing --to flag returns argument parser error")
    func missingToFlag() throws {
        let input = FixtureManager.markdownFile()
        // 不帶 --to，直接 convert <file>
        let result = try CLITestHelper.run(["convert", input])
        #expect(!result.succeeded, "missing --to should fail")
    }
}
