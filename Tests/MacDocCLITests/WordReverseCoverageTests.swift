// WordReverseCoverageTests.swift
// format-alignment-engine task 1.6 — `macdoc word reverse --coverage` e2e.
// Verifies the dual-track coverage report is emitted and parsable
// (`format-alignment-pipeline`, «DSL-form coverage measurement»; Decision 2).
//
// The synthetic docx is built via OOXMLSwift's public authoring API — a
// self-contained, non-private fixture (the env-gated real templates stay out
// of CI per Decision 5). md→docx is deliberately NOT used as the fixture
// source: it has a pre-existing `try!` crash on parse failure
// (MarkdownToWordConverter.swift), unrelated to this task.

import XCTest
import Foundation
import OOXMLSwift

final class WordReverseCoverageTests: XCTestCase {

    /// The macdoc-side synthetic template: a minimal two-paragraph docx built
    /// straight from the authoring op-log, no converter and no ZIPFoundation
    /// dependency in this test target.
    private func makeSyntheticDocx(at url: URL) throws {
        var doc = WordDocument.emptyAuthoringDocument()
        try doc.apply(operations: [
            .appendParagraph(in: nil, paragraph: ParagraphPayload(text: "第一段落。", paraId: "P1")),
            .appendParagraph(in: nil, paragraph: ParagraphPayload(text: "第二段落。", paraId: "P2")),
        ])
        try doc.writeAuthoringPackage(to: url)
    }

    /// `word reverse --coverage` prints a per-part DSL/raw report + an aggregate
    /// line to stdout, parsable by downstream tooling.
    func testWordReverseCoverageEmitsParsableReport() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let docx = tmp.appendingPathComponent("sample.docx")
        try makeSyntheticDocx(at: docx)

        let out = tmp.appendingPathComponent("sample.mdocx.swift")
        let result = try CLITestHelper.run(
            ["word", "reverse", docx.path, "--to-mdocx", out.path, "--coverage"])
        XCTAssertEqual(result.exitCode, 0, "reverse --coverage failed: \(result.stderr)")

        let stdout = result.stdout
        XCTAssertTrue(stdout.contains("Coverage report"), "missing header:\n\(stdout)")
        XCTAssertTrue(stdout.contains("word/document.xml"), "missing per-part line:\n\(stdout)")
        XCTAssertTrue(stdout.contains("DSL"), "missing DSL column:\n\(stdout)")
        XCTAssertNotNil(stdout.range(of: #"Aggregate:\s*[0-9.]+% DSL"#, options: .regularExpression),
                        "missing parsable aggregate line:\n\(stdout)")
        // Phase A baseline: reverse carries all parts on the raw channel → 0% DSL.
        XCTAssertNotNil(stdout.range(of: #"Aggregate:\s*0\.0% DSL"#, options: .regularExpression),
                        "Phase A must report 0.0% DSL baseline:\n\(stdout)")
    }

    /// Without --coverage, no report is printed — pins the default-false flag
    /// behavior (swift-argument-parser: default-false so presence toggles on;
    /// default-true would make the flag a no-op).
    func testWordReverseWithoutCoveragePrintsNoReport() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrc-off-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let docx = tmp.appendingPathComponent("s.docx")
        try makeSyntheticDocx(at: docx)

        let out = tmp.appendingPathComponent("s.mdocx.swift")
        let result = try CLITestHelper.run(["word", "reverse", docx.path, "--to-mdocx", out.path])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertFalse(result.stdout.contains("Coverage report"),
                       "coverage report leaked without --coverage:\n\(result.stdout)")
    }
}
