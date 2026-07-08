// WordReverseSlotTests.swift
// format-alignment-engine Phase D task 4.1 — `macdoc word reverse
// --slot <name>=<paragraph-id>` (repeatable) produces a parameterized
// script (`template-content-slots`; design Q2: Swift function parameters).

import XCTest
import Foundation
import OOXMLSwift

final class WordReverseSlotTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func makeSyntheticDocx(at url: URL) throws {
        var doc = WordDocument.emptyAuthoringDocument()
        try doc.apply(operations: [
            .appendParagraph(in: nil, paragraph: ParagraphPayload(
                text: "原文のタイトル", styleId: "Title", paraId: "P1")),
            .appendParagraph(in: nil, paragraph: ParagraphPayload(text: "原文の本文。", paraId: "P2")),
        ])
        try doc.writeAuthoringPackage(to: url)
    }

    /// --slot produces the parameterized form; executing it with the default
    /// call-site arguments reproduces the reference byte-equal.
    func testSlotFlagProducesParameterizedScript() throws {
        let dir = try makeTempDir()
        let docx = dir.appendingPathComponent("t.docx")
        try makeSyntheticDocx(at: docx)
        let reference = try RawPartChannel.readAllParts(from: docx)

        let out = dir.appendingPathComponent("t.mdocx.swift")
        let result = try CLITestHelper.run([
            "word", "reverse", docx.path, "--to-mdocx", out.path,
            "--slot", "title=P1", "--slot", "body=P2",
        ])
        XCTAssertEqual(result.exitCode, 0, result.stderr)

        let script = try String(contentsOf: out, encoding: .utf8)
        XCTAssertTrue(script.contains("func makeDocument("), "parameterized form expected")
        XCTAssertTrue(script.contains("title: String,"))
        XCTAssertTrue(script.contains("body: String"))

        // Defaults reproduce the reference byte-equal.
        let log = try ScriptImporter.parse(source: script)
        var doc = WordDocument.emptyAuthoringDocument()
        try doc.apply(operations: log.entries.map(\.op))
        let rebuiltURL = dir.appendingPathComponent("rebuilt.docx")
        try doc.writeAuthoringPackage(to: rebuiltURL)
        let rebuilt = try RawPartChannel.readAllParts(from: rebuiltURL)
        XCTAssertTrue(PartFidelity.stageB(reference: reference, rebuilt: rebuilt))
    }

    /// Malformed and unusable designations fail loudly with a 中文 message.
    func testBadSlotDesignationsFailLoudly() throws {
        let dir = try makeTempDir()
        let docx = dir.appendingPathComponent("t.docx")
        try makeSyntheticDocx(at: docx)
        let out = dir.appendingPathComponent("t.mdocx.swift")

        let malformed = try CLITestHelper.run([
            "word", "reverse", docx.path, "--to-mdocx", out.path, "--slot", "titleP1",
        ])
        XCTAssertNotEqual(malformed.exitCode, 0)
        XCTAssertTrue(malformed.stderr.contains("無效的 slot 指定"), malformed.stderr)

        let unknown = try CLITestHelper.run([
            "word", "reverse", docx.path, "--to-mdocx", out.path, "--slot", "title=NOPE",
        ])
        XCTAssertNotEqual(unknown.exitCode, 0)
        XCTAssertTrue(unknown.stderr.contains("無法建立"), unknown.stderr)
    }
}
