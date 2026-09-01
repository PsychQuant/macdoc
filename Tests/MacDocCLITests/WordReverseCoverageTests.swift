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

        // Explicit paragraphs-only path — the mode that carries no
        // byte-equal DSL claim, so the report is honestly all-raw (Phase A
        // baseline semantics). The full-fidelity default's nonzero coverage
        // is pinned by WordReverseFullFidelityTests (Phase C task 3.1).
        let out = tmp.appendingPathComponent("sample.mdocx.swift")
        let result = try CLITestHelper.run(
            ["word", "reverse", docx.path, "--to-mdocx", out.path,
             "--coverage", "--paragraphs-only"])
        XCTAssertEqual(result.exitCode, 0, "reverse --coverage failed: \(result.stderr)")

        let stdout = result.stdout
        XCTAssertTrue(stdout.contains("Coverage report"), "missing header:\n\(stdout)")
        XCTAssertTrue(stdout.contains("word/document.xml"), "missing per-part line:\n\(stdout)")
        XCTAssertTrue(stdout.contains("DSL"), "missing DSL column:\n\(stdout)")
        XCTAssertNotNil(stdout.range(of: #"Aggregate:\s*[0-9.]+% DSL"#, options: .regularExpression),
                        "missing parsable aggregate line:\n\(stdout)")
        // Paragraphs-only carries no byte-equal DSL claim → all-raw → 0%.
        XCTAssertNotNil(stdout.range(of: #"Aggregate:\s*0\.0% DSL"#, options: .regularExpression),
                        "paragraphs-only must report the all-raw 0.0% baseline:\n\(stdout)")
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

    /// A docx whose paragraphs carry no `w14:paraId`. Direct body mutation
    /// bypasses the authoring chokepoints that would stamp one — the same
    /// technique OOXMLSwift's own bypass-path test uses. This is what a
    /// document produced by some Word versions looks like (#176).
    private func makeParaIdlessDocx(at url: URL) throws {
        var doc = WordDocument()
        doc.body.children.append(.paragraph(Paragraph(runs: [Run(text: "no paraId here")])))
        try DocxWriter.write(doc, to: url)
    }

    /// `--coverage` is usable as a pure diagnostic: no `--to-mdocx`, no script
    /// written. Pins #177 — the report is the documented step for deciding
    /// *whether* to produce the script, so requiring the output path made the
    /// caller produce the very artifact they were still deciding about.
    func testCoverageRunsWithoutOutputPath() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrc-noout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let docx = tmp.appendingPathComponent("s.docx")
        try makeSyntheticDocx(at: docx)

        let result = try CLITestHelper.run(["word", "reverse", docx.path, "--coverage"])
        XCTAssertEqual(result.exitCode, 0, "coverage-only run failed: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("Coverage report"),
                      "coverage-only must still print the report:\n\(result.stdout)")

        let produced = try FileManager.default.contentsOfDirectory(atPath: tmp.path)
            .filter { $0.hasSuffix(".swift") }
        XCTAssertTrue(produced.isEmpty,
                      "coverage-only must not write a script; found: \(produced)")
    }

    /// Neither `--to-mdocx` nor `--coverage` leaves the command with nothing to
    /// do — it must say so rather than default to one of them (#177).
    func testMissingBothOutputAndCoverageFails() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrc-neither-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let docx = tmp.appendingPathComponent("s.docx")
        try makeSyntheticDocx(at: docx)

        let result = try CLITestHelper.run(["word", "reverse", docx.path])
        XCTAssertNotEqual(result.exitCode, 0, "must refuse when there is nothing to produce")
        let combined = result.stderr + result.stdout
        XCTAssertTrue(combined.contains("--to-mdocx") && combined.contains("--coverage"),
                      "the error must name both ways out:\n\(combined)")
    }

    /// A paraId-less document reports the actionable root cause and the
    /// alternative path, instead of a bare 0.0% that reads as "hopeless" (#176).
    func testParaIdlessDocumentNamesRootCauseAndAlternative() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrc-noid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let docx = tmp.appendingPathComponent("legacy.docx")
        try makeParaIdlessDocx(at: docx)

        let result = try CLITestHelper.run(["word", "reverse", docx.path, "--coverage"])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("paragraph-no-paraId"),
                      "the report must name the root cause:\n\(result.stdout)")
        XCTAssertTrue(result.stdout.contains("--paragraphs-only"),
                      "the report must point at the alternative path:\n\(result.stdout)")
    }

    /// The note is conditioned on the root cause, not emitted for every raw
    /// part. A document that DOES carry paraIds must not be told to reach for
    /// `--paragraphs-only` (#176) — the sibling parts are raw by design.
    func testParaIdBearingDocumentGetsNoRootCauseNote() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrc-hasid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let docx = tmp.appendingPathComponent("s.docx")
        try makeSyntheticDocx(at: docx)

        let result = try CLITestHelper.run(["word", "reverse", docx.path, "--coverage"])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertFalse(result.stdout.contains("paragraph-no-paraId"),
                       "root-cause note leaked onto a paraId-bearing document:\n\(result.stdout)")
    }
}

