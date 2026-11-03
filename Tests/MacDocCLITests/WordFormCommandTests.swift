// WordFormCommandTests.swift — `macdoc word form classify|apply` and the
// `word reverse --slot` follow-up note (macdoc#249, change
// docx-form-normalization).

import XCTest
import Foundation
import DocxForm
import OOXMLSwift

final class WordFormCommandTests: XCTestCase {
    private static let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    private static let w14 = "http://schemas.microsoft.com/office/word/2010/wordml"

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wfc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func run(_ text: String, rPr: String = "") -> String {
        "<w:r>\(rPr)<w:t xml:space=\"preserve\">\(text)</w:t></w:r>"
    }

    private func paragraph(_ id: String, pPr: String = "", _ content: String) -> String {
        "<w:p w14:paraId=\"\(id)\">\(pPr)\(content)</w:p>"
    }

    /// A minimal but complete package: content types, relationships, styles,
    /// numbering and a main part holding a body paragraph, a table with a field
    /// cell and a checkbox cell, and a numbered (box-bullet) paragraph.
    private func makeForm(at url: URL) throws {
        let sized = "<w:rPr><w:sz w:val=\"18\"/></w:rPr>"
        let body = paragraph("0000B0D1", run("申請人資料"))
            + "<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w=\"3000\"/><w:gridCol w:w=\"3000\"/></w:tblGrid><w:tr>"
            + "<w:tc><w:tcPr><w:tcW w:w=\"3000\" w:type=\"dxa\"/></w:tcPr>"
            + paragraph("0000C0DE", run("王小明", rPr: sized)) + "<w:p/></w:tc>"
            + "<w:tc><w:tcPr><w:tcW w:w=\"3000\" w:type=\"dxa\"/></w:tcPr>"
            + paragraph("0000C0EE", run(")  \u{25A1}", rPr: sized)) + "</w:tc>"
            + "</w:tr></w:tbl>"
            + paragraph("0000A0A0", pPr: "<w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr>", run("第一個選項"))
            + "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/></w:sectPr>"
        let document = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<w:document xmlns:w=\"\(Self.w)\" xmlns:w14=\"\(Self.w14)\"><w:body>\(body)</w:body></w:document>"
        let numbering = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<w:numbering xmlns:w=\"\(Self.w)\"><w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"0\">"
            + "<w:lvlText w:val=\"\u{25A1}\"/></w:lvl></w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>"
        let contentTypes = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
            + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
            + "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
            + "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>"
            + "<Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/>"
            + "<Override PartName=\"/word/numbering.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\"/>"
            + "</Types>"
        let rels = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>"
            + "</Relationships>"
        let documentRels = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
            + "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering\" Target=\"numbering.xml\"/>"
            + "</Relationships>"
        let styles = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<w:styles xmlns:w=\"\(Self.w)\"><w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val=\"22\"/></w:rPr></w:rPrDefault></w:docDefaults></w:styles>"
        try DocxPackage.write([
            .init(path: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            .init(path: "_rels/.rels", data: Data(rels.utf8)),
            .init(path: "word/document.xml", data: Data(document.utf8)),
            .init(path: "word/_rels/document.xml.rels", data: Data(documentRels.utf8)),
            .init(path: "word/styles.xml", data: Data(styles.utf8)),
            .init(path: "word/numbering.xml", data: Data(numbering.utf8)),
        ], to: url)
    }

    private func documentXML(_ url: URL) throws -> String {
        let entry = try DocxPackage.read(from: url).first { $0.path == "word/document.xml" }!
        return String(decoding: entry.data, as: UTF8.self)
    }

    // MARK: The classify command lists every addressable paragraph

    func testClassifyListsKindsInDocumentOrder() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        try makeForm(at: form)
        let result = try CLITestHelper.run(["word", "form", "classify", form.path])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(result.stdout.split(separator: "\n").map(String.init), [
            "0000B0D1\tbody\t申請人資料",
            "0000C0DE\ttable-field\t王小明",
            "0000C0EE\tcheckbox-line\t)  \u{25A1}",
            "0000A0A0\tlist-checkbox\t第一個選項",
        ])
    }

    func testClassifyMissingInput() throws {
        let result = try CLITestHelper.run(["word", "form", "classify", "/nonexistent/form.docx"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("找不到輸入檔案:"), result.stderr)
    }

    // MARK: apply

    func testApplyFieldAndCheckboxFont() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let output = dir.appendingPathComponent("filled.docx")
        try makeForm(at: form)
        let result = try CLITestHelper.run([
            "word", "form", "apply", form.path, "--to-docx", output.path,
            "--field", "0000C0DE", "--checkbox-font", "標楷體",
        ])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stderr.contains("填寫欄字級：9 pt"), result.stderr)
        XCTAssertTrue(result.stderr.contains("已寫入:"), result.stderr)
        let xml = try documentXML(output)
        XCTAssertTrue(xml.contains("<w:vAlign w:val=\"center\"/>"))
        XCTAssertTrue(xml.contains("<w:jc w:val=\"left\"/>"))
        XCTAssertFalse(xml.contains("<w:p/>"), "empty sibling of the field removed")
        XCTAssertTrue(xml.contains("w:eastAsia=\"標楷體\""))
        // Every other part is unchanged.
        let before = try DocxPackage.read(from: form)
        let after = try DocxPackage.read(from: output)
        XCTAssertEqual(before.map(\.path), after.map(\.path))
        for (b, a) in zip(before, after) where b.path != "word/document.xml" {
            XCTAssertEqual(b.data, a.data, b.path)
        }
    }

    func testApplyBadIdLeavesNoOutput() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let output = dir.appendingPathComponent("filled.docx")
        try makeForm(at: form)
        let result = try CLITestHelper.run([
            "word", "form", "apply", form.path, "--to-docx", output.path,
            "--field", "0000C0DE", "--remove", "DEADBEEF",
        ])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("DEADBEEF"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testApplyRefusesExistingOutputWithoutForce() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let output = dir.appendingPathComponent("filled.docx")
        try makeForm(at: form)
        try Data("keep".utf8).write(to: output)
        let result = try CLITestHelper.run([
            "word", "form", "apply", form.path, "--to-docx", output.path, "--remove", "0000B0D1",
        ])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("--force"), result.stderr)
        XCTAssertEqual(try Data(contentsOf: output), Data("keep".utf8))
    }

    func testApplyWithoutOperationIsAUsageError() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        try makeForm(at: form)
        let result = try CLITestHelper.run([
            "word", "form", "apply", form.path, "--to-docx", dir.appendingPathComponent("o.docx").path,
        ])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("至少要指定一個操作"), result.stderr)
    }

    func testApplyTickListAndInsertAfter() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let output = dir.appendingPathComponent("filled.docx")
        try makeForm(at: form)
        let result = try CLITestHelper.run([
            "word", "form", "apply", form.path, "--to-docx", output.path,
            "--tick-list", "0000A0A0", "--insert-after", "0000B0D1=補充說明",
        ])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let xml = try documentXML(output)
        XCTAssertTrue(xml.contains("<w:t>\u{25A0}</w:t>"))
        XCTAssertFalse(xml.contains("w:numPr"))
        XCTAssertTrue(xml.contains("補充說明"))
    }

    // MARK: Reverse names the follow-up for slots that need one

    func testReverseNotesTableFieldSlotOnly() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let script = dir.appendingPathComponent("form.mdocx.swift")
        try makeForm(at: form)
        let result = try CLITestHelper.run([
            "word", "reverse", form.path, "--to-mdocx", script.path,
            "--slot", "applicant=0000C0DE", "--slot", "intro=0000B0D1",
        ])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let notes = result.stderr.split(separator: "\n").filter { $0.hasPrefix("note: slot") }
        XCTAssertEqual(notes.count, 1, result.stderr)
        XCTAssertTrue(notes[0].contains("applicant"))
        XCTAssertTrue(notes[0].contains("table-field"))
        XCTAssertTrue(notes[0].contains("--field 0000C0DE"))

        // The script itself is exactly what the exporter produces without the note logic.
        let parts = try RawPartChannel.readAllParts(from: form)
        let expected = try ScriptExporter.exportSwift(
            log: try ReverseExtractor.reverse(parts: parts).log,
            slots: [SlotDesignation(name: "applicant", paraId: "0000C0DE"),
                    SlotDesignation(name: "intro", paraId: "0000B0D1")])
        XCTAssertEqual(try String(contentsOf: script, encoding: .utf8), expected)
    }
}
