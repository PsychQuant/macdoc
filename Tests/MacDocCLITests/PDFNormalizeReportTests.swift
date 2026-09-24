import XCTest
import PDFToLaTeXCore
@testable import MacDocCLI

/// `macdoc pdf normalize` 對頁碼還原（PsychQuant/macdoc#9）與圖片寬度還原（#10）的回報。
/// 這兩步在 pdf-to-latex-swift 0.3.0 的 `normalizeProject` 內自動執行；沒有處理到的項目
/// 原始碼保持原樣，所以 CLI 必須把原因印出來，否則使用者無從得知哪些頁、哪些圖要自己處理。
final class PDFNormalizeReportTests: XCTestCase {
    private func report(pages: [PageCounterNote] = [], figures: [FigureWidthResolution] = [],
                        unreadable: [String] = []) -> NormalizeProjectReport {
        NormalizeProjectReport(
            mainFileChanged: true, preambleFileChanged: false, preambleURL: nil,
            documentClassFixed: false, mathOperatorsAdded: [], currencyDollarsEscaped: 0,
            figureWidthResolutions: figures, unreadableResponseFiles: unreadable, pageCounterNotes: pages)
    }

    func testNothingToReportPrintsNothing() {
        XCTAssertEqual(MacDoc.PDF.Normalize.pageAndFigureSummary(report()), [])
    }

    func testPageCounterSummaryCountsInsertionsAndListsEveryProblem() {
        let lines = MacDoc.PDF.Normalize.pageAndFigureSummary(report(pages: [
            PageCounterNote(line: 3, kind: .counterInserted(page: 5)),
            PageCounterNote(line: 9, kind: .counterInserted(page: 8)),
            PageCounterNote(line: 14, kind: .legacyCounterMoved(page: 11)),
            PageCounterNote(line: 20, kind: .conflictingCounterBeforeChapter(existing: 7, expected: 12)),
            PageCounterNote(line: 31, kind: .chapterTitleNotFound),
        ]))
        XCTAssertEqual(lines.first, "  page counters: 2 inserted, 1 legacy moved")
        XCTAssertTrue(lines.contains { $0.contains("line 20") && $0.contains("7") && $0.contains("12") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("line 31") }, "\(lines)")
        XCTAssertEqual(lines.count, 3, "\(lines)")
    }

    func testFigureSummaryCountsRoutineOutcomesAndListsActionableOnes() {
        let lines = MacDoc.PDF.Normalize.pageAndFigureSummary(report(figures: [
            FigureWidthResolution(path: "figures/a.png", page: 2, line: 10, outcome: .widthApplied(fraction: 0.5, widthPoints: 297.6)),
            FigureWidthResolution(path: "figures/b.png", page: 2, line: 11, outcome: .explicitSizePreserved),
            FigureWidthResolution(path: "figures/c.png", page: nil, line: 12, outcome: .noPageContext),
            FigureWidthResolution(path: "figures/d.png", page: 3, line: 20, outcome: .noMatchingFigure),
            FigureWidthResolution(path: "figures/e.png", page: 4, line: 30, outcome: .invalidBoundingBox([0, 0, 2, 1])),
            FigureWidthResolution(path: "figures/f.png", page: 5, line: 40, outcome: .metadataUnavailable("manifest.json 不存在")),
        ], unreadable: ["responses/page_006.json"]))
        XCTAssertEqual(lines.first, "  figure widths: 1 applied, 1 already sized, 1 without page context")
        for path in ["figures/d.png", "figures/e.png", "figures/f.png"] {
            XCTAssertTrue(lines.contains { $0.contains(path) }, "\(path) 未列出：\(lines)")
        }
        for path in ["figures/a.png", "figures/b.png", "figures/c.png"] {
            XCTAssertFalse(lines.contains { $0.contains(path) }, "例行結果不必逐筆列出：\(lines)")
        }
        XCTAssertTrue(lines.contains { $0.contains("manifest.json 不存在") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("responses/page_006.json") }, "\(lines)")
    }

    /// 端到端：CLI 真的走到 0.3.0 的兩個步驟，並把摘要印出來。
    func testNormalizeCommandRestoresPageCounterAndReportsIt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("normalize-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let tex = dir.appendingPathComponent("accumulated.tex")
        try Data("""
        \\documentclass{book}
        \\begin{document}
        %% === Page 5 ===
        \\chapter{Intro}
        Text.
        \\includegraphics{figures/p5_1.png}
        \\end{document}

        """.utf8).write(to: tex)

        let result = try CLITestHelper.run(["pdf", "normalize", "--project", dir.path])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("page counters:"), result.stdout)
        XCTAssertTrue(result.stdout.contains("figures/p5_1.png"), "無 metadata 的圖必須回報：\(result.stdout)")
        XCTAssertTrue(try String(contentsOf: tex, encoding: .utf8).contains("\\setcounter{page}{5}"))
    }
}
