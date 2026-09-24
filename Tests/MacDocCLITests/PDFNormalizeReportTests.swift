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

    /// 每一種 Outcome 都放進來：例行的三種各放不同筆數（抓寫死計數），需要處理的七種各一筆，
    /// 逐筆核對路徑、頁碼、行號與原因（抓「把某種問題誤歸為例行」）。
    func testFigureSummaryCountsRoutineOutcomesAndListsEveryActionableOne() {
        let applied = (0..<3).map { FigureWidthResolution(path: "figures/ok\($0).png", page: 2, line: 10 + $0, outcome: .widthApplied(fraction: 0.5, widthPoints: 297.6)) }
        let sized = (0..<2).map { FigureWidthResolution(path: "figures/sized\($0).png", page: 2, line: 20 + $0, outcome: .explicitSizePreserved) }
        let noContext = (0..<4).map { FigureWidthResolution(path: "figures/nopage\($0).png", page: nil, line: 30 + $0, outcome: .noPageContext) }
        let actionable: [(FigureWidthResolution, String)] = [
            (FigureWidthResolution(path: "figures/d.png", page: 3, line: 41, outcome: .noMatchingFigure), "responses 沒有這張圖"),
            (FigureWidthResolution(path: "figures/e.png", page: 4, line: 42, outcome: .ambiguousFigure), "多筆互相矛盾"),
            (FigureWidthResolution(path: "figures/f.png", page: 5, line: 43, outcome: .invalidBoundingBox([0, 0, 2, 1])), "bbox 不合法"),
            (FigureWidthResolution(path: "figures/g.png", page: 6, line: 44, outcome: .widthNotRepresentable(1e-9)), "寬度太小"),
            (FigureWidthResolution(path: "figures/h.png", page: 7, line: 45, outcome: .missingPageRecord), "manifest.json 沒有該頁"),
            (FigureWidthResolution(path: "figures/i.png", page: 8, line: 46, outcome: .missingImageFile), "圖檔不存在"),
            (FigureWidthResolution(path: "figures/j.png", page: 9, line: 47, outcome: .metadataUnavailable("manifest.json 不存在")), "manifest.json 不存在"),
        ]
        let lines = MacDoc.PDF.Normalize.pageAndFigureSummary(report(
            figures: applied + sized + noContext + actionable.map(\.0), unreadable: ["responses/page_006.json"]))

        XCTAssertEqual(lines.first, "  figure widths: 3 applied, 2 already sized, 4 without page context")
        for (figure, reason) in actionable {
            let matches = lines.filter { $0.contains(figure.path) }
            XCTAssertEqual(matches.count, 1, "\(figure.path) 應恰好列出一次：\(lines)")
            let line = matches.first ?? ""
            XCTAssertTrue(line.contains("page \(figure.page!)") && line.contains("line \(figure.line)") && line.contains(reason), line)
        }
        for routine in applied + sized + noContext {
            XCTAssertFalse(lines.contains { $0.contains(routine.path) }, "例行結果不必逐筆列出：\(lines)")
        }
        XCTAssertTrue(lines.contains { $0.contains("responses/page_006.json") }, "\(lines)")
        XCTAssertEqual(lines.count, 1 + actionable.count + 1, "\(lines)")
    }

    /// pdf-to-latex-swift 0.4.0（#211、#207、#210、#215）新增的紀錄：例行的計數，需要處理的逐筆列出。
    func testSummaryCoversThe040Notes() {
        let full = NormalizeProjectReport(
            mainFileChanged: true, preambleFileChanged: false, preambleURL: nil,
            documentClassFixed: false, mathOperatorsAdded: [], currencyDollarsEscaped: 0,
            figureWidthResolutions: [
                FigureWidthResolution(path: "figures/p002-a.png", page: 2, line: 5,
                                      outcome: .widthApplied(fraction: 0.5, widthPoints: 306), replacedLegacyWidth: true),
                FigureWidthResolution(path: "figures/p002-b.png", page: 2, line: 6,
                                      outcome: .widthApplied(fraction: 0.4, widthPoints: 244.8)),
            ],
            pageCounterNotes: [
                PageCounterNote(line: 3, kind: .counterInserted(page: 1)),
                PageCounterNote(line: 3, kind: .numberingInserted(style: .roman)),
                PageCounterNote(line: 9, kind: .pageLabelUnsupported(page: 4, label: "A-1")),
                PageCounterNote(line: 12, kind: .pageLabelMissing(page: 7)),
            ],
            chapterOpening: .openAnyAdded,
            splitListNotes: [
                SplitListNote(line: 20, kind: .listRejoined(environment: "itemize")),
                SplitListNote(line: 30, kind: .unmodelledListCommand(name: "trivlist")),
                SplitListNote(line: 40, kind: .unmatchedEnvironmentEnd),
            ])
        let lines = MacDoc.PDF.Normalize.pageAndFigureSummary(full)
        XCTAssertTrue(lines.contains("  page counters: 1 inserted, 0 legacy moved, 1 numbering switches"), "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("line 9") && $0.contains("A-1") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("line 12") && $0.contains("第 7 頁") }, "\(lines)")
        XCTAssertTrue(lines.contains("  figure widths: 2 applied (1 upgraded from the 0.3.0 format), 0 already sized, 0 without page context"), "\(lines)")
        XCTAssertTrue(lines.contains("  chapter opening: openany added (a chapter starts on an even page)"), "\(lines)")
        XCTAssertTrue(lines.contains("  split lists: 1 rejoined"), "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("line 30") && $0.contains("trivlist") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("line 40") && $0.contains("\\end") }, "\(lines)")
    }

    /// 明確的 openright 會保留，但使用者要知道偶數頁起始的章節前會多一張空白頁；其餘四種結果不印。
    func testChapterOpeningOnlyReportsWhatNeedsAttention() {
        func lines(_ outcome: ChapterOpeningOutcome) -> [String] {
            MacDoc.PDF.Normalize.pageAndFigureSummary(NormalizeProjectReport(
                mainFileChanged: false, preambleFileChanged: false, preambleURL: nil,
                documentClassFixed: false, mathOperatorsAdded: [], currencyDollarsEscaped: 0,
                chapterOpening: outcome))
        }
        XCTAssertTrue(lines(.explicitOpenRightKept).first?.contains("openright") == true)
        for quiet in [ChapterOpeningOutcome.notNeeded, .alreadyOpenAny, .oneSide, .notBookClass] {
            XCTAssertEqual(lines(quiet), [], "\(quiet)")
        }
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
