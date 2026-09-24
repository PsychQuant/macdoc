// WordReverseSlotE2ETests.swift
// PsychQuant/macdoc#193 — CLI end-to-end slot verification.
//
// WordReverseSlotTests.swift only checks that the exported script's SOURCE
// contains the right parameter names / defaults, and that the UNCHANGED
// defaults reproduce the reference byte-equal. It never replays a CHANGED
// slot value through the real `macdoc word render` binary and reads the
// rebuilt docx back — the exact gap #193 names ("不只搜尋生成程式的參數名稱").
//
// These tests close that gap for all three slot forms, each driving the
// actual CLI binary (via CLITestHelper, not a library call):
//   1. DSL-spellable paragraph slot   — `Paragraph(id:){ }` block.
//   2. Op-level slot                  — a formatted multi-run paragraph
//      whose pPr/rPr rides the `// @op` raw escape inside an otherwise
//      DSL-spellable document.
//   3. Raw-channel slot               — the whole word/document.xml rides
//      the raw channel as a single carried part (`// @slot-raw`).
//
// Every case asserts the substituted text appears, the old text is gone,
// AND a neighbouring paragraph's text is untouched — "changed only the
// designated paragraph", not just "script contains the right identifier".

import XCTest
import Foundation
import OOXMLSwift

final class WordReverseSlotE2ETests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrs-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// Reads `word/document.xml` out of a (rebuilt) docx as a UTF-8 string.
    private func documentXML(of docx: URL) throws -> String {
        let parts = try RawPartChannel.readAllParts(from: docx)
        guard let data = parts["word/document.xml"] else {
            XCTFail("docx has no word/document.xml: \(docx.path)")
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Case 1: DSL-spellable paragraph slot

    private func makeDSLSlotDocx(at url: URL) throws {
        var doc = WordDocument.emptyAuthoringDocument()
        try doc.apply(operations: [
            .appendParagraph(in: nil, paragraph: ParagraphPayload(
                text: "標題原文", styleId: "Title", paraId: "TITLE001")),
            .appendParagraph(in: nil, paragraph: ParagraphPayload(
                text: "鄰居段落，不應被改動", paraId: "NEIGH001")),
        ])
        try doc.writeAuthoringPackage(to: url)
    }

    /// A DSL-spellable paragraph slot: changing the call-site default in the
    /// exported script and actually running `macdoc word render` must change
    /// ONLY the designated paragraph's text in the rebuilt docx.
    func testDSLSlotRenderWithChangedValueChangesOnlyDesignatedParagraph() throws {
        let dir = try makeTempDir()
        let docx = dir.appendingPathComponent("dsl.docx")
        try makeDSLSlotDocx(at: docx)

        let script = dir.appendingPathComponent("dsl.mdocx.swift")
        let reverseResult = try CLITestHelper.run([
            "word", "reverse", docx.path, "--to-mdocx", script.path,
            "--slot", "title=TITLE001",
        ])
        XCTAssertEqual(reverseResult.exitCode, 0, reverseResult.stderr)

        var source = try String(contentsOf: script, encoding: .utf8)
        XCTAssertTrue(source.contains("Paragraph(id: \"TITLE001\", style: .title)"),
                      "must be a DSL-spellable paragraph slot, not op-level or raw-channel")
        XCTAssertTrue(source.contains("title: \"標題原文\""),
                      "call-site default must carry the original text")
        source = source.replacingOccurrences(
            of: "title: \"標題原文\"", with: "title: \"標題已改\"")
        try source.write(to: script, atomically: true, encoding: .utf8)

        let rebuilt = dir.appendingPathComponent("dsl-rebuilt.docx")
        let renderResult = try CLITestHelper.run([
            "word", "render", script.path, "--to-docx", rebuilt.path,
        ])
        XCTAssertEqual(renderResult.exitCode, 0, renderResult.stderr)

        let xml = try documentXML(of: rebuilt)
        XCTAssertTrue(xml.contains("標題已改"), "substituted text must be present")
        XCTAssertFalse(xml.contains("標題原文"), "old text must be gone")
        XCTAssertTrue(xml.contains("鄰居段落，不應被改動"),
                      "neighbouring paragraph's text must be untouched")
    }

    // MARK: - Case 2: op-level slot on a formatted multi-run paragraph

    private func makeOpLevelSlotDocx(at url: URL) throws {
        var doc = WordDocument.emptyAuthoringDocument()
        try doc.apply(operations: [
            .appendParagraph(in: nil, paragraph: ParagraphPayload(
                text: "鄰居段落，不應被改動", paraId: "NEIGH002")),
            .appendParagraph(in: nil, paragraph: ParagraphPayload(
                text: "", paraId: "HEAD0001",
                indentFirstLine: 180, indentFirstLineChars: 100,
                paragraphMarkRun: RunPayload(
                    text: "", fontAscii: "Times New Roman", sizeHalfPoints: 36))),
            .setRuns(target: ElementID(rawString: "w14:paraId=HEAD0001"), runs: [
                RunPayload(text: "原文の見出し", bold: true,
                           fontEastAsia: "ＭＳ ゴシック", sizeHalfPoints: 36),
            ]),
        ])
        try doc.writeAuthoringPackage(to: url)
    }

    /// An op-level slot: the target paragraph's rich pPr/rPr rides the
    /// `// @op` raw escape instead of a typed `Paragraph(id:){ }` block, in
    /// an otherwise DSL-spellable document. Substitution must replace only
    /// the run text — formatting (bold / eastAsia font / first-line-char
    /// indent) survives — and the neighbouring DSL paragraph is untouched.
    func testOpLevelSlotRenderWithChangedValueChangesOnlyDesignatedParagraph() throws {
        let dir = try makeTempDir()
        let docx = dir.appendingPathComponent("oplevel.docx")
        try makeOpLevelSlotDocx(at: docx)

        let script = dir.appendingPathComponent("oplevel.mdocx.swift")
        let reverseResult = try CLITestHelper.run([
            "word", "reverse", docx.path, "--to-mdocx", script.path,
            "--slot", "heading=HEAD0001",
        ])
        XCTAssertEqual(reverseResult.exitCode, 0, reverseResult.stderr)

        var source = try String(contentsOf: script, encoding: .utf8)
        XCTAssertTrue(source.contains("// @slot heading HEAD0001"),
                      "must be an op-level slot (// @slot), not DSL-spellable or raw-channel")
        XCTAssertFalse(source.contains("Paragraph(id: \"HEAD0001\")"),
                       "the formatted paragraph must NOT get a typed DSL block")
        XCTAssertTrue(source.contains("heading: \"原文の見出し\""),
                      "call-site default must carry the extracted run text")
        source = source.replacingOccurrences(
            of: "heading: \"原文の見出し\"", with: "heading: \"新しい見出し\"")
        try source.write(to: script, atomically: true, encoding: .utf8)

        let rebuilt = dir.appendingPathComponent("oplevel-rebuilt.docx")
        let renderResult = try CLITestHelper.run([
            "word", "render", script.path, "--to-docx", rebuilt.path,
        ])
        XCTAssertEqual(renderResult.exitCode, 0, renderResult.stderr)

        let xml = try documentXML(of: rebuilt)
        XCTAssertTrue(xml.contains("新しい見出し"), "substituted text must be present")
        XCTAssertFalse(xml.contains("原文の見出し"), "old text must be gone")
        XCTAssertTrue(xml.contains("ＭＳ ゴシック"), "run eastAsia font must survive")
        XCTAssertTrue(xml.contains("<w:b/>"), "run bold must survive")
        XCTAssertTrue(xml.contains("w:firstLineChars=\"100\""), "pPr first-line-char indent must survive")
        XCTAssertTrue(xml.contains("鄰居段落，不應被改動"),
                      "neighbouring DSL paragraph's text must be untouched")
    }

    // MARK: - Case 3: raw-channel slot (whole document.xml on the raw channel)

    private func makeRawChannelSlotDocx(at url: URL) throws {
        var doc = WordDocument()
        var neighbour = Paragraph(runs: [Run(text: "鄰居段落，不應被改動")])
        neighbour.w14ParaId = "NEIGH003"
        var target = Paragraph(runs: [Run(text: "原始欄位值")])
        target.w14ParaId = "FIELD0001"
        // A paragraph with NO w14:paraId at all forces the entire
        // word/document.xml onto the raw channel ("paragraph-no-paraId") —
        // the same part-level all-or-nothing fallback a foreign-form table
        // triggers, without needing to hand-write raw table XML. See
        // ooxml-swift's ParaIdGenerator / ReverseExtractor.extractParagraph.
        let legacy = Paragraph(runs: [Run(text: "沒有 paraId 的段落")])
        doc.body.children.append(.paragraph(neighbour))
        doc.body.children.append(.paragraph(target))
        doc.body.children.append(.paragraph(legacy))
        try DocxWriter.write(doc, to: url)
    }

    /// A raw-channel slot (`// @slot-raw`): the whole document.xml rides the
    /// raw channel as one carried part, and substitution is run-level
    /// surgery on the carried XML. Only the designated paragraph's text may
    /// change — the neighbour AND the paraId-less paragraph that forced the
    /// raw fallback in the first place must stay byte-identical.
    func testRawChannelSlotRenderWithChangedValueChangesOnlyDesignatedParagraph() throws {
        let dir = try makeTempDir()
        let docx = dir.appendingPathComponent("raw.docx")
        try makeRawChannelSlotDocx(at: docx)

        let script = dir.appendingPathComponent("raw.mdocx.swift")
        let reverseResult = try CLITestHelper.run([
            "word", "reverse", docx.path, "--to-mdocx", script.path,
            "--slot", "field=FIELD0001",
        ])
        XCTAssertEqual(reverseResult.exitCode, 0, reverseResult.stderr)

        var source = try String(contentsOf: script, encoding: .utf8)
        XCTAssertTrue(source.contains("// @slot-raw field FIELD0001"),
                      "must be a raw-channel slot (// @slot-raw), confirming word/document.xml rode the raw channel")
        XCTAssertTrue(source.contains("field: \"原始欄位值\""),
                      "call-site default must carry the designated paragraph's text")
        source = source.replacingOccurrences(
            of: "field: \"原始欄位值\"", with: "field: \"已核准\"")
        try source.write(to: script, atomically: true, encoding: .utf8)

        let rebuilt = dir.appendingPathComponent("raw-rebuilt.docx")
        let renderResult = try CLITestHelper.run([
            "word", "render", script.path, "--to-docx", rebuilt.path,
        ])
        XCTAssertEqual(renderResult.exitCode, 0, renderResult.stderr)

        let xml = try documentXML(of: rebuilt)
        XCTAssertTrue(xml.contains("已核准"), "substituted text must be present")
        XCTAssertFalse(xml.contains("原始欄位值"), "old text must be gone")
        XCTAssertTrue(xml.contains("鄰居段落，不應被改動"),
                      "neighbouring paragraph's text must be untouched")
        XCTAssertTrue(xml.contains("沒有 paraId 的段落"),
                      "the paraId-less paragraph that forced the raw fallback must itself be untouched")
    }

    // MARK: - Case 3b (gated): raw-channel slot on a real official template

    /// Resolves the REC-O-01 fixture under MACDOC_TEMPLATE_DIR, or XCTSkips
    /// cleanly when the env var is absent — per PsychQuant/macdoc#193, a
    /// gated real-template variant must never fail a normal (ungated) run.
    private func recFixtureURL() throws -> URL {
        guard let dir = ProcessInfo.processInfo.environment["MACDOC_TEMPLATE_DIR"], !dir.isEmpty else {
            throw XCTSkip("set MACDOC_TEMPLATE_DIR to run the real-template raw-channel slot test (PsychQuant/macdoc#193)")
        }
        let url = URL(fileURLWithPath: dir)
            .appendingPathComponent("REC-O-01-新案審查送件核對單-20250220公告.docx")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("MACDOC_TEMPLATE_DIR set but REC-O-01 fixture missing at \(url.path)")
        }
        return url
    }

    /// Real-template variant of case 3: REC-O-01 is a genuine official form
    /// whose document.xml rides the raw channel because of a table (not a
    /// missing paraId), exercising `// @slot-raw` against a real release
    /// artifact rather than only a synthetic fixture. Third-party content —
    /// never committed to the repo, only read from MACDOC_TEMPLATE_DIR.
    func testRawChannelSlotOnRealTemplateChangesOnlyDesignatedParagraph() throws {
        let fixture = try recFixtureURL()
        let dir = try makeTempDir()

        let reference = try RawPartChannel.readAllParts(from: fixture)
        let refXML = try documentXML(of: fixture)
        guard let idRange = refXML.range(of: #"w14:paraId=""#),
              let idEnd = refXML[idRange.upperBound...].firstIndex(of: "\"") else {
            return XCTFail("REC-O-01 fixture must carry at least one w14:paraId")
        }
        let paraId = String(refXML[idRange.upperBound..<idEnd])

        let script = dir.appendingPathComponent("rec.mdocx.swift")
        let reverseResult = try CLITestHelper.run([
            "word", "reverse", fixture.path, "--to-mdocx", script.path,
            "--slot", "field=\(paraId)",
        ])
        XCTAssertEqual(reverseResult.exitCode, 0, reverseResult.stderr)

        var source = try String(contentsOf: script, encoding: .utf8)
        XCTAssertTrue(source.contains("// @slot-raw field \(paraId)"),
                      "REC-O-01 must exercise the raw-channel slot form")
        guard let defaultRange = source.range(of: #"field: ""#),
              let defaultEnd = source[defaultRange.upperBound...].firstIndex(of: "\"") else {
            return XCTFail("script must carry a call-site default for the slot")
        }
        let defaultValue = String(source[defaultRange.upperBound..<defaultEnd])
        source = source.replacingOccurrences(
            of: "field: \"\(defaultValue)\"", with: "field: \"覆核完成\"")
        try source.write(to: script, atomically: true, encoding: .utf8)

        let rebuilt = dir.appendingPathComponent("rec-rebuilt.docx")
        let renderResult = try CLITestHelper.run([
            "word", "render", script.path, "--to-docx", rebuilt.path,
        ])
        XCTAssertEqual(renderResult.exitCode, 0, renderResult.stderr)

        let outXML = try documentXML(of: rebuilt)
        XCTAssertTrue(outXML.contains("覆核完成"), "substituted text must be present")
        let rebuiltParts = try RawPartChannel.readAllParts(from: rebuilt)
        for (path, bytes) in reference where path != "word/document.xml" {
            XCTAssertEqual(rebuiltParts[path], bytes, "non-document part \(path) must be byte-identical")
        }
    }
}
