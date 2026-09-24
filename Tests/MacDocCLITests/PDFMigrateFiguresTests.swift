import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
import PDFToLaTeXCore
@testable import MacDocCLI

/// PsychQuant/macdoc#222：`macdoc pdf migrate-figures` 把 pdf-to-latex 0.4.0 之前轉寫的專案
/// 重新裁切成帶頁碼的圖檔名（不呼叫 AI）。遷移本身由 `PageTranscriber.migrateFigureCrops`
/// 實作（pdf-to-latex-swift 0.5.0）；這裡驗證 CLI 的摘要與端到端行為。
final class PDFMigrateFiguresTests: XCTestCase {

    // MARK: - Summary

    func testSummaryCountsRoutineOutcomesAndListsActionableOnes() {
        let lines = MacDoc.PDF.MigrateFigures.summary([
            FigureMigrationOutcome(page: 1, kind: .migrated(figuresProcessed: 2)),
            FigureMigrationOutcome(page: 2, kind: .migrated(figuresProcessed: 1)),
            FigureMigrationOutcome(page: 3, kind: .unchanged),
            FigureMigrationOutcome(page: 4, kind: .noFigureData),
            FigureMigrationOutcome(page: 5, kind: .noPageTexFile),
            FigureMigrationOutcome(page: 6, kind: .noPageImage),
            FigureMigrationOutcome(page: 7, kind: .writeFailed("磁碟已滿")),
            FigureMigrationOutcome(page: 8, kind: .unchanged, notes: ["fig9 的 bbox 不合法"]),
        ])
        XCTAssertEqual(lines.first, "figure 遷移：已遷移 2 頁（3 張圖），未變動 2 頁，沒有 figure 資料 1 頁")
        XCTAssertTrue(lines.contains { $0.contains("第 5 頁") && $0.contains("page-0005.tex") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("第 6 頁") && $0.contains("pdf render") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("第 7 頁") && $0.contains("磁碟已滿") }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("第 8 頁") && $0.contains("fig9 的 bbox 不合法") }, "\(lines)")
        for routine in [1, 2, 3, 4] {
            XCTAssertFalse(lines.contains { $0.contains("第 \(routine) 頁") }, "例行結果不逐頁列出：\(lines)")
        }
    }

    func testSummaryOfNothingToDo() {
        XCTAssertEqual(MacDoc.PDF.MigrateFigures.summary([]), ["figure 遷移：已遷移 0 頁（0 張圖），未變動 0 頁，沒有 figure 資料 0 頁"])
    }

    // MARK: - End to end

    private var projectDir: URL!

    override func setUpWithError() throws {
        projectDir = FileManager.default.temporaryDirectory.appendingPathComponent("migrate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: projectDir)
    }

    private func writeRedPageImage(page: Int) throws -> String {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let url = projectDir.appendingPathComponent(String(format: "pages/page-%04d.png", page))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url.path
    }

    private func writeManifest(pages: [PageRecord]) throws {
        let manifest = ProjectManifest(
            schemaVersion: 1, createdAt: "", updatedAt: "", projectName: "t",
            sourcePDF: projectDir.appendingPathComponent("source.pdf").path,
            projectRoot: projectDir.path, pages: pages, blocks: [])
        try ManifestStore().save(manifest, to: ProjectLayout.manifestURL(for: projectDir))
    }

    private func writeResponses(page: Int) throws {
        let dir = projectDir.appendingPathComponent("responses")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let result = PageResult(
            page: page, latex: "",
            figures: [FigureRegion(id: "fig1", bbox: [0.1, 0.1, 0.4, 0.3], caption: nil)],
            confidence: nil, notes: nil)
        try JSONEncoder().encode(PageTranscriptionResponse(pages: [result]))
            .write(to: dir.appendingPathComponent("pages-all.json"))
    }

    func testMigratesAnOldProject() throws {
        let image = try writeRedPageImage(page: 3)
        try writeManifest(pages: [
            PageRecord(number: 1, width: 612, height: 792, rotation: 0, renderedImagePath: nil, renderedDPI: nil),
            PageRecord(number: 2, width: 612, height: 792, rotation: 0, renderedImagePath: nil, renderedDPI: nil),
            PageRecord(number: 3, width: 612, height: 792, rotation: 0, renderedImagePath: image, renderedDPI: nil),
        ])
        try writeResponses(page: 3)
        let tex = projectDir.appendingPathComponent("tex/page-0003.tex")
        try FileManager.default.createDirectory(at: tex.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Intro.\n\\includegraphics{figures/fig1.png}\n".write(to: tex, atomically: true, encoding: .utf8)

        let result = try CLITestHelper.run([
            "pdf", "migrate-figures", "--project", projectDir.path, "--first-page", "3", "--last-page", "3",
        ])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("已遷移 1 頁（1 張圖）"), result.stdout)
        let rewritten = try String(contentsOf: tex, encoding: .utf8)
        XCTAssertTrue(rewritten.contains("figures/p003-fig1.png"), rewritten)
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectDir.appendingPathComponent("figures/p003-fig1.png").path))
    }

    /// `tex/` 不存在時不得以空內容覆寫既有的 `accumulated.tex`（pdf-to-latex-swift 0.5.0 的保證）。
    func testLeavesAccumulatedTexAloneWhenTexDirectoryIsMissing() throws {
        try writeManifest(pages: [
            PageRecord(number: 1, width: 612, height: 792, rotation: 0, renderedImagePath: nil, renderedDPI: nil),
        ])
        let accumulated = projectDir.appendingPathComponent("accumulated.tex")
        let sentinel = "\\documentclass{book}\n% user content\n"
        try sentinel.write(to: accumulated, atomically: true, encoding: .utf8)

        let result = try CLITestHelper.run(["pdf", "migrate-figures", "--project", projectDir.path])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("第 1 頁"), result.stdout)
        XCTAssertEqual(try String(contentsOf: accumulated, encoding: .utf8), sentinel)
    }
}
