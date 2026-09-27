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

    /// PsychQuant/macdoc#231 — a baseline that carries parts the typed model
    /// never produces, the way a document saved by Word does: a theme reached
    /// through a relationship, plus a custom XML part. A fixture written by
    /// `makeBaseline` alone cannot catch part loss, because it only contains
    /// what the writer itself emits.
    private func makeBaselineWithUnmodeledParts(texts: [String]) throws -> URL {
        let plain = try makeBaseline(texts: texts)
        defer { try? FileManager.default.removeItem(at: plain) }
        let dir = try ZipHelper.unzip(plain)
        defer { ZipHelper.cleanup(dir) }

        let theme = dir.appendingPathComponent("word/theme/theme1.xml")
        try FileManager.default.createDirectory(
            at: theme.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Issue231"><a:themeElements/></a:theme>"#.utf8)
            .write(to: theme)
        let custom = dir.appendingPathComponent("customXml/item1.xml")
        try FileManager.default.createDirectory(
            at: custom.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"<?xml version="1.0" encoding="UTF-8"?><issue231 keep="me"/>"#.utf8).write(to: custom)

        func insert(_ snippet: String, before closing: String, in relativePath: String) throws {
            let url = dir.appendingPathComponent(relativePath)
            let text = try String(contentsOf: url, encoding: .utf8)
            guard let range = text.range(of: closing, options: .backwards) else {
                throw NSError(domain: "ExecutorTests", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "\(closing) not found in \(relativePath)"])
            }
            try Data(text.replacingCharacters(in: range, with: snippet + closing).utf8).write(to: url)
        }
        try insert(
            #"<Relationship Id="rIdIssue231Theme" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>"#,
            before: "</Relationships>", in: "word/_rels/document.xml.rels")
        try insert(
            #"<Override PartName="/word/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/><Override PartName="/customXml/item1.xml" ContentType="application/xml"/>"#,
            before: "</Types>", in: "[Content_Types].xml")

        let url = makeTempURL(prefix: "baseline-unmodeled")
        try ZipHelper.zip(dir, to: url)
        return url
    }

    private func partBytes(of docx: URL) throws -> [String: Data] {
        let dir = try ZipHelper.unzip(docx)
        defer { ZipHelper.cleanup(dir) }
        var parts: [String: Data] = [:]
        let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey])
        while let file = files?.nextObject() as? URL {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let name = file.standardizedFileURL.path
                .replacingOccurrences(of: dir.standardizedFileURL.path + "/", with: "")
            parts[name] = try Data(contentsOf: file)
        }
        return parts
    }

    // MARK: - Spec scenarios

    /// PsychQuant/macdoc#231: applying a step must leave every part the step
    /// does not touch byte-identical, and must not drop parts.
    func testApplyPreservesPartsTheStepDoesNotTouch() throws {
        let baseline = try makeBaselineWithUnmodeledParts(texts: ["intro", "body"])
        let output = makeTempURL(prefix: "out-231")
        defer {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: output)
        }

        let manifest = Manifest(
            baseline: baseline.path,
            output: output.path,
            steps: [.insertParagraph(InsertParagraphStep(
                anchor: .afterText("intro"), content: "inserted by 231"))]
        )
        let result = try Executor().apply(manifest: manifest, baselineURL: baseline, outputURL: output)
        XCTAssertEqual(result.appliedStepCount, 1)

        let before = try partBytes(of: baseline)
        let after = try partBytes(of: output)
        XCTAssertEqual(Set(after.keys), Set(before.keys),
                       "parts were added or dropped: missing \(Set(before.keys).subtracting(after.keys).sorted()), extra \(Set(after.keys).subtracting(before.keys).sorted())")
        for (name, bytes) in before where name != "word/document.xml" {
            XCTAssertEqual(after[name], bytes, "\(name) changed although the step only edits word/document.xml")
        }
        let document = try XCTUnwrap(after["word/document.xml"])
        XCTAssertTrue(String(decoding: document, as: UTF8.self).contains("inserted by 231"))
    }

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
