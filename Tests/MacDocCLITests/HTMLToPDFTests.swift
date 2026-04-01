import Testing
import Foundation

/// HTML → PDF 轉換測試 (#69)
struct HTMLToPDFTests {

    // MARK: - Route 存在性

    @Test("html → pdf route 存在")
    func htmlToPdfRouteExists() throws {
        let input = FixtureManager.htmlFile()
        let outputPath = FixtureManager.outputPath("output-html.pdf")
        let result = try CLITestHelper.convert(
            to: "pdf", input: input, flags: ["--output", outputPath]
        )
        // 不應該回傳「不支援」錯誤
        #expect(
            !result.stderr.contains("不支援從 .html 轉換到 pdf"),
            "route should exist, got: \(result.stderr)"
        )
    }

    // MARK: - stdout 限制

    @Test("html → pdf 不支援 stdout")
    func htmlToPdfRejectsStdout() throws {
        let input = FixtureManager.htmlFile()
        let result = try CLITestHelper.convert(
            to: "pdf", input: input, flags: ["--stdout"]
        )
        #expect(!result.succeeded, "should fail with --stdout")
        #expect(
            result.stderr.contains("不支援 stdout"),
            "should mention stdout not supported"
        )
    }

    // MARK: - playwright 可用時的 E2E 測試

    @Test("html → pdf 產生 PDF 檔案")
    func htmlToPdfProducesFile() throws {
        // 直接嘗試轉換
        let input = FixtureManager.htmlFile()
        let outputPath = FixtureManager.outputPath("output-e2e.pdf")
        let result = try CLITestHelper.convert(
            to: "pdf", input: input, flags: ["--output", outputPath]
        )

        if result.stderr.contains("playwright") && !result.succeeded {
            // playwright 未安裝，跳過
            print("⚠️ playwright 未安裝，跳過 E2E 測試")
            return
        }

        #expect(result.succeeded, "should succeed, stderr: \(result.stderr)")
        #expect(
            FileManager.default.fileExists(atPath: outputPath),
            "PDF output file should exist"
        )
        let size = (try? FileManager.default.attributesOfItem(atPath: outputPath)[.size] as? Int) ?? 0
        #expect(size > 0, "PDF file should be non-empty")
    }

    // MARK: - 自動生成輸出路徑

    @Test("html → pdf 未指定 output 時自動生成 .pdf")
    func htmlToPdfAutoOutput() throws {
        // 建立一個可控位置的 HTML 檔案
        let htmlContent = "<h1>Auto Output Test</h1><p>Content</p>"
        let inputURL = FixtureManager.outputDir
            .appendingPathComponent("auto-test.html")
        try htmlContent.write(to: inputURL, atomically: true, encoding: .utf8)

        let result = try CLITestHelper.convert(to: "pdf", input: inputURL.path)

        if result.stderr.contains("playwright") && !result.succeeded {
            print("⚠️ playwright 未安裝，跳過自動路徑測試")
            return
        }

        // 應該自動生成 auto-test.pdf
        let expectedPDF = FixtureManager.outputDir
            .appendingPathComponent("auto-test.pdf")
        #expect(result.succeeded, "should succeed, stderr: \(result.stderr)")
        #expect(
            FileManager.default.fileExists(atPath: expectedPDF.path),
            "auto-generated PDF should exist at \(expectedPDF.path)"
        )

        // 清理
        try? FileManager.default.removeItem(at: expectedPDF)
    }
}
