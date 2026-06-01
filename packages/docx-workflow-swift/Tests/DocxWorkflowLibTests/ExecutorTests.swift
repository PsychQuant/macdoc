// ExecutorTests — §6.3 of macdoc-docx-workflow-cli.
//
// Covers spec.md Requirements:
// - "Executor applies steps in manifest order" (sequential resolution +
//   abort-before-write)
// - "Phase-2c-pending step types compile but warn at runtime"
// - "DocxWorkflowLib library boundary" (WordDocument handle path)

import XCTest
import DocxWorkflowLib

final class ExecutorTests: XCTestCase {

    // MARK: - Fixture helpers

    private func makeTempURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).docx")
    }

    /// Builds a fixture .docx with the given paragraph texts.
    private func makeBaseline(texts: [String]) throws -> URL {
        var doc = WordDocument()
        for text in texts {
            doc.appendParagraph(Paragraph(text: text))
        }
        let url = makeTempURL(prefix: "baseline")
        try DocxWriter.writeData(doc).write(to: url)
        return url
    }

    // MARK: - Spec scenarios

    func testInsertImageStepEmitsWarningAndSkips() throws {
        // Spec: "insert_image step is decoded but skipped with warning"
        let baseline = try makeBaseline(texts: ["caption A"])
        let output = makeTempURL(prefix: "out")
        defer {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: output)
        }

        let manifest = Manifest(
            baseline: baseline.path,
            output: output.path,
            steps: [
                .insertImage(InsertImageStep(
                    anchor: .afterText("caption A"),
                    path: "fig.png"
                ))
            ]
        )

        var warnings: [String] = []
        let result = try Executor().apply(
            manifest: manifest,
            baselineURL: baseline,
            outputURL: output,
            warnHandler: { warnings.append($0) }
        )

        // Warning emitted, step skipped, output still written.
        XCTAssertEqual(warnings.count, 1, "Expected exactly one warning for insert_image")
        let w = warnings[0]
        XCTAssertTrue(w.contains("insert_image"), "Warning should name the step type: \(w)")
        XCTAssertTrue(w.contains("ooxml-swift#71"), "Warning should cite the tracker: \(w)")

        XCTAssertEqual(result.appliedStepCount, 0)
        XCTAssertEqual(result.skippedPendingStepCount, 1)
        XCTAssertEqual(result.skippedStepTypes, ["insert_image"])

        // Output written.
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }

    func testManifestWithOnlyPendingStepsProducesEmittedOutput() throws {
        // Spec: "Manifest with only Phase-2c-pending steps still produces valid output"
        let baseline = try makeBaseline(texts: ["only"])
        let output = makeTempURL(prefix: "out")

        let manifest = Manifest(
            baseline: baseline.path,
            output: output.path,
            steps: [
                .insertImage(InsertImageStep(anchor: .afterText("only"), path: "f.png")),
                .insertTable(InsertTableStep(anchor: .afterText("only"), rows: 2, columns: 2)),
            ]
        )

        var warnings: [String] = []
        let result = try Executor().apply(
            manifest: manifest,
            baselineURL: baseline,
            outputURL: output,
            warnHandler: { warnings.append($0) }
        )

        XCTAssertEqual(warnings.count, 2, "Both pending steps should warn")
        XCTAssertEqual(result.appliedStepCount, 0)
        XCTAssertEqual(result.skippedPendingStepCount, 2)

        // Output written + non-empty + ZIP signature.
        let bytes = try Data(contentsOf: output)
        XCTAssertGreaterThan(bytes.count, 0)
        XCTAssertEqual(Array(bytes.prefix(4)), [0x50, 0x4B, 0x03, 0x04],
            "Output should be a valid OOXML ZIP container")
    }

    func testAnchorFailureAbortsBeforeWrite() throws {
        // Spec: "Anchor failure aborts execution before write"
        let baseline = try makeBaseline(texts: ["only"])
        let output = makeTempURL(prefix: "out")

        let manifest = Manifest(
            baseline: baseline.path,
            output: output.path,
            steps: [
                // First step: pending → skip (no apply)
                .insertImage(InsertImageStep(anchor: .afterText("only"), path: "f.png")),
                // Second step: anchor that doesn't match → must throw
                .insertImage(InsertImageStep(anchor: .afterText("NonExistent"), path: "g.png")),
            ]
        )

        XCTAssertThrowsError(
            try Executor().apply(manifest: manifest, baselineURL: baseline, outputURL: output)
        ) { error in
            guard let e = error as? AnchorError else {
                XCTFail("Expected AnchorError, got \(error)")
                return
            }
            guard case .notFound = e else {
                XCTFail("Expected .notFound, got \(e)")
                return
            }
        }

        // Output MUST NOT exist.
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path),
            "Output file must not be written when Executor throws")
    }

    func testMixedRunPopulatesResult() throws {
        // Mixed functional + pending — verify ExecutorResult fields.
        let baseline = try makeBaseline(texts: ["only"])
        let output = makeTempURL(prefix: "out")

        let manifest = Manifest(
            baseline: baseline.path,
            output: output.path,
            steps: [
                // Two pending steps (different types)
                .insertImage(InsertImageStep(anchor: .afterText("only"), path: "f.png")),
                .insertEquation(InsertEquationStep(anchor: .afterText("only"), omml: "<m:e/>")),
            ]
        )

        var warnings: [String] = []
        let result = try Executor().apply(
            manifest: manifest,
            baselineURL: baseline,
            outputURL: output,
            warnHandler: { warnings.append($0) }
        )

        XCTAssertEqual(result.appliedStepCount, 0)
        XCTAssertEqual(result.skippedPendingStepCount, 2)
        XCTAssertEqual(Set(result.skippedStepTypes), Set(["insert_image", "insert_equation"]))
        XCTAssertEqual(warnings.count, 2)
    }
}
