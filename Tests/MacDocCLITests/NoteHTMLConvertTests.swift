import XCTest

/// Smoke coverage for `macdoc convert --to html file.note`.
///
/// Guards against the "#78 refactor passed with zero tests exercising
/// NoteToHTML" gap flagged by #81. Uses the on-disk `test-files/*.note`
/// fixture (Option B per #81 diagnosis); skips cleanly when absent.
final class NoteHTMLConvertTests: XCTestCase {

    func testNoteToHTMLSmoke() throws {
        let fixture = try CLITestHelper.noteFixture()

        // Note → HTML produces a directory (interactive player with index.html + media/),
        // not a single file. Use a directory path for --output.
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdoc-note-html-smoke-\(UUID().uuidString).html")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        // Note → HTML requires --css dark or --css light (per macdoc CLI contract).
        let result = try CLITestHelper.convert(
            to: "html",
            input: fixture.path,
            flags: ["--output", outputDir.path, "--css", "dark"]
        )

        XCTAssertEqual(
            result.exitCode, 0,
            "macdoc convert --to html SHALL exit 0\nstderr: \(result.stderr)"
        )

        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputDir.path, isDirectory: &isDirectory),
            "output SHALL exist at \(outputDir.path)"
        )
        XCTAssertTrue(
            isDirectory.boolValue,
            "note → html output SHALL be a directory (interactive player with index.html + media/)"
        )

        let indexURL = outputDir.appendingPathComponent("index.html")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: indexURL.path),
            "output SHALL include index.html"
        )

        let mediaURL = outputDir.appendingPathComponent("media", isDirectory: true)
        var mediaIsDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: mediaURL.path, isDirectory: &mediaIsDirectory),
            "output SHALL include media/ for rendered note assets"
        )
        XCTAssertTrue(mediaIsDirectory.boolValue, "media/ SHALL be a directory")

        // Branch assertions by fixture type:
        // - Real fixtures (test-files/*.note) carry rich content → strict
        //   "media ≥ 1 asset" + ">750 KB index.html" floors per #81 calibration.
        // - Synthetic fixtures (NoteFixtureGenerator output, per #100) have no
        //   media + minimal strokes → only structural assertions apply.
        // Detection: synthetic fixtures live in $TMPDIR with the
        // `macdoc-synthetic-fixture-` prefix (per CLITestHelper.swift, no
        // cache subdirectory since #100 round-2 fix).
        let isSyntheticFixture = fixture.lastPathComponent.contains("macdoc-synthetic-fixture")

        let mediaFiles = try FileManager.default.contentsOfDirectory(
            at: mediaURL,
            includingPropertiesForKeys: nil
        ).filter { !$0.hasDirectoryPath }
        if !isSyntheticFixture {
            XCTAssertGreaterThanOrEqual(
                mediaFiles.count, 1,
                "media/ SHALL contain at least one image or audio asset (rich fixture)"
            )
        }

        let indexData = try Data(contentsOf: indexURL)
        if !isSyntheticFixture {
            // Baseline 2026-05-02 using `test-files/筆記 2026-03-20 15_25_20.note`:
            // 1,569,860 bytes. The 750 KB floor catches empty-shell regressions
            // while leaving headroom for renderer/template changes.
            XCTAssertGreaterThan(
                indexData.count, 750_000,
                "index.html SHALL be a non-trivial rendered player, not a tiny shell (rich fixture)"
            )
        }

        let content = try String(contentsOf: indexURL, encoding: .utf8)
        XCTAssertGreaterThan(content.count, 0, "index.html SHALL be non-empty")
        XCTAssertTrue(
            content.lowercased().contains("<html"),
            "index.html SHALL contain an <html tag"
        )
    }
}
