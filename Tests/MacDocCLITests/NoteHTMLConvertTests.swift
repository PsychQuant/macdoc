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

        let content = try String(contentsOf: indexURL, encoding: .utf8)
        XCTAssertGreaterThan(content.count, 0, "index.html SHALL be non-empty")
        XCTAssertTrue(
            content.lowercased().contains("<html"),
            "index.html SHALL contain an <html tag"
        )
    }
}
