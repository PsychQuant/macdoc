// WordReverseFullFidelityTests.swift
// format-alignment-engine Phase C task 3.1 — full-fidelity (all-parts) is
// the `word reverse` default; `--paragraphs-only` opts out to the old
// paragraphs-only reverse (`ooxml-script-transcode`, «All-parts raw
// channel»; Decision 4 migration plan).

import XCTest
import Foundation
import OOXMLSwift

final class WordReverseFullFidelityTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func makeSyntheticDocx(at url: URL) throws {
        var doc = WordDocument.emptyAuthoringDocument()
        try doc.apply(operations: [
            .appendParagraph(in: nil, paragraph: ParagraphPayload(
                text: "第一段落。", styleId: "Body", paraId: "P1")),
            .appendParagraph(in: nil, paragraph: ParagraphPayload(text: "第二段落。", paraId: "P2")),
        ])
        try doc.writeAuthoringPackage(to: url)
    }

    /// Default run (no flags) is full-fidelity: executing the produced script
    /// rebuilds the package byte-equal (Stage B) — every part present.
    func testDefaultReverseIsFullFidelityAndPassesStageB() throws {
        let dir = try makeTempDir()
        let docx = dir.appendingPathComponent("sample.docx")
        try makeSyntheticDocx(at: docx)
        let reference = try RawPartChannel.readAllParts(from: docx)

        let out = dir.appendingPathComponent("sample.mdocx.swift")
        let result = try CLITestHelper.run(["word", "reverse", docx.path, "--to-mdocx", out.path])
        XCTAssertEqual(result.exitCode, 0, result.stderr)

        // Execute the script in-process and compare part sets.
        let script = try String(contentsOf: out, encoding: .utf8)
        let log = try ScriptImporter.parse(source: script)
        var doc = WordDocument.emptyAuthoringDocument()
        try doc.apply(operations: log.entries.map(\.op))
        let rebuiltURL = dir.appendingPathComponent("rebuilt.docx")
        try doc.writeAuthoringPackage(to: rebuiltURL)
        let rebuilt = try RawPartChannel.readAllParts(from: rebuiltURL)

        XCTAssertTrue(PartFidelity.stageB(reference: reference, rebuilt: rebuilt),
                      "default full-fidelity reverse must rebuild Stage B byte-equal")
    }

    /// --paragraphs-only reproduces the old behavior: a paragraphs-only
    /// script (no carried parts), so the rebuild is NOT full part-set equal.
    func testParagraphsOnlyOptOutReproducesOldBehavior() throws {
        let dir = try makeTempDir()
        let docx = dir.appendingPathComponent("sample.docx")
        try makeSyntheticDocx(at: docx)

        let out = dir.appendingPathComponent("sample.mdocx.swift")
        let result = try CLITestHelper.run(
            ["word", "reverse", docx.path, "--to-mdocx", out.path, "--paragraphs-only"])
        XCTAssertEqual(result.exitCode, 0, result.stderr)

        let script = try String(contentsOf: out, encoding: .utf8)
        XCTAssertFalse(script.contains("carryPart"),
                       "paragraphs-only script must not carry sibling parts")
        XCTAssertTrue(script.contains("Paragraph(id:"),
                      "paragraphs-only script keeps the DSL paragraph blocks")
    }

    /// Default full-fidelity + --coverage reports a nonzero DSL share for a
    /// self-authored docx (document.xml upgrades through ReverseExtractor).
    func testDefaultCoverageReportsUpgradedDocument() throws {
        let dir = try makeTempDir()
        let docx = dir.appendingPathComponent("sample.docx")
        try makeSyntheticDocx(at: docx)

        let out = dir.appendingPathComponent("sample.mdocx.swift")
        let result = try CLITestHelper.run(
            ["word", "reverse", docx.path, "--to-mdocx", out.path, "--coverage"])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Coverage report"), result.stdout)
        // document.xml upgraded → per-part line says dsl and aggregate > 0.
        XCTAssertNotNil(
            result.stdout.range(of: #"word/document\.xml\s+dsl"#, options: .regularExpression),
            "document.xml must report the dsl channel:\n\(result.stdout)")
        XCTAssertNil(
            result.stdout.range(of: #"Aggregate:\s*0\.0% DSL"#, options: .regularExpression),
            "aggregate must be nonzero once document.xml upgrades:\n\(result.stdout)")
    }
}
