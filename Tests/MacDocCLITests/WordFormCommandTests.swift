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
    private func makeForm(at url: URL, numberingOverride: String? = nil, extraBody: String = "") throws {
        let sized = "<w:rPr><w:sz w:val=\"18\"/></w:rPr>"
        let body = paragraph("0000B0D1", run("申請人資料"))
            + "<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w=\"3000\"/><w:gridCol w:w=\"3000\"/></w:tblGrid><w:tr>"
            + "<w:tc><w:tcPr><w:tcW w:w=\"3000\" w:type=\"dxa\"/></w:tcPr>"
            + paragraph("0000C0DE", run("王小明", rPr: sized)) + "<w:p/></w:tc>"
            + "<w:tc><w:tcPr><w:tcW w:w=\"3000\" w:type=\"dxa\"/></w:tcPr>"
            + paragraph("0000C0EE", run(")  \u{25A1}", rPr: sized)) + "</w:tc>"
            + "</w:tr></w:tbl>"
            + paragraph("0000A0A0", pPr: "<w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr>", run("第一個選項"))
            + extraBody
            + "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/></w:sectPr>"
        let document = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<w:document xmlns:w=\"\(Self.w)\" xmlns:w14=\"\(Self.w14)\"><w:body>\(body)</w:body></w:document>"
        let numbering = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<w:numbering xmlns:w=\"\(Self.w)\"><w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"0\">"
            + "<w:lvlText w:val=\"\u{25A1}\"/></w:lvl></w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>"
        let numberingPart = numberingOverride ?? numbering
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
            .init(path: "word/numbering.xml", data: Data(numberingPart.utf8)),
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

    /// A numbering part an XML parser rejects disables list-checkbox detection
    /// only, and the command says so on stderr.
    func testClassifyNotesAnUnreadableNumberingPart() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let broken = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<w:numbering xmlns:w=\"\(Self.w)\"><w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"0\">"
            + "<w:lvlText w:val=\"\u{25A1}\" w:val=\"%1.\"/></w:lvl></w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>"
        try makeForm(at: form, numberingOverride: broken)
        let result = try CLITestHelper.run(["word", "form", "classify", form.path])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stderr.contains("word/numbering.xml 無法解析"), result.stderr)
        XCTAssertTrue(result.stdout.contains("0000A0A0\tbody\t"), result.stdout)
    }

    /// Document text cannot put terminal control sequences on stdout. A raw
    /// control byte (classify runs no XML parser over the main part) reaches
    /// the preview and is replaced by a space; a character reference to a
    /// character XML 1.0 does not allow is not decoded at all (#252), so it is
    /// shown as written. Neither puts an ESC on stdout.
    func testClassifyPreviewReplacesControlCharacters() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        try makeForm(at: form, extraBody: paragraph("0000E5C0", run("前\u{1B}[31m後"))
                                           + paragraph("0000E5C1", run("左&#x1B;[31m右")))
        let result = try CLITestHelper.run(["word", "form", "classify", form.path])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertFalse(result.stdout.unicodeScalars.contains("\u{1B}"))
        XCTAssertTrue(result.stdout.contains("0000E5C0\tbody\t前 [31m後"), result.stdout)
        XCTAssertTrue(result.stdout.contains("0000E5C1\tbody\t左&#x1B;[31m右"), result.stdout)
    }

    /// #252: classify reads only the two parts it needs, but the entry-name
    /// check still covers the whole package.
    func testClassifyRefusesASuspiciousEntryName() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let crafted = dir.appendingPathComponent("crafted.docx")
        try makeForm(at: form)
        try DocxPackage.write(try DocxPackage.read(from: form) + [DocxPackage.Entry(path: "../evil.xml", data: Data("<a/>".utf8))],
                              to: crafted)
        let result = try CLITestHelper.run(["word", "form", "classify", crafted.path])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("../evil.xml"), result.stderr)
        XCTAssertTrue(result.stdout.isEmpty, result.stdout)
    }

    /// The refused name is quoted in the message with its control characters
    /// blanked, for classify and apply alike (#252 verify R1).
    func testRefusedEntryNameReachesStderrWithoutControlCharacters() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let crafted = dir.appendingPathComponent("crafted.docx")
        try makeForm(at: form)
        let name = "../\u{1B}[2Jevil\nx.xml"
        try DocxPackage.write(try DocxPackage.read(from: form) + [DocxPackage.Entry(path: name, data: Data("<a/>".utf8))],
                              to: crafted)
        for arguments in [["word", "form", "classify", crafted.path],
                          ["word", "form", "apply", crafted.path, "--to-docx", dir.appendingPathComponent("o.docx").path,
                           "--checkbox-font", "標楷體"]] {
            let result = try CLITestHelper.run(arguments)
            XCTAssertNotEqual(result.exitCode, 0, arguments.joined(separator: " "))
            XCTAssertFalse(result.stderr.unicodeScalars.contains("\u{1B}"), result.stderr)
            XCTAssertTrue(result.stderr.contains("../ [2Jevil x.xml"), result.stderr)
        }
    }

    /// A paraId is eight hex digits; a crafted one (here an ESC sequence from
    /// a character reference) is not printed, only counted.
    func testClassifySkipsParaIdsThatAreNotEightHexDigits() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        try makeForm(at: form, extraBody: paragraph("&#x1B;[31mXX", run("偽造")))
        let result = try CLITestHelper.run(["word", "form", "classify", form.path])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertFalse(result.stdout.unicodeScalars.contains("\u{1B}"))
        XCTAssertFalse(result.stdout.contains("偽造"), result.stdout)
        XCTAssertEqual(result.stdout.split(separator: "\n").count, 4, result.stdout)
        XCTAssertTrue(result.stderr.contains("略過 1 個 w14:paraId"), result.stderr)
    }

    /// Bidirectional overrides can reorder the terminal line; they become spaces.
    func testClassifyPreviewReplacesBidirectionalOverrides() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        try makeForm(at: form, extraBody: paragraph("0000B1D1", run("甲&#x202E;乙&#x2028;丙")))
        let result = try CLITestHelper.run(["word", "form", "classify", form.path])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("0000B1D1\tbody\t甲 乙 丙"), result.stdout)
    }

    /// Error messages quote names from the file (here a tag name holding the
    /// C1 control U+0085); they reach stderr with control characters blanked.
    func testErrorMessagesFromTheFileAreSanitized() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("broken.docx")
        let document = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<w:document xmlns:w=\"\(Self.w)\"><w:body></a\u{85}b></w:body></w:document>"
        try DocxPackage.write([.init(path: "word/document.xml", data: Data(document.utf8))], to: form)
        for arguments in [["word", "form", "classify", form.path],
                          ["word", "form", "apply", form.path, "--to-docx", dir.appendingPathComponent("o.docx").path,
                           "--checkbox-font", "標楷體"]] {
            let result = try CLITestHelper.run(arguments)
            XCTAssertNotEqual(result.exitCode, 0, arguments.joined(separator: " "))
            XCTAssertFalse(result.stderr.unicodeScalars.contains("\u{85}"), result.stderr)
            XCTAssertTrue(result.stderr.contains("沒有對應的開始標籤"), result.stderr)
        }
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

    /// `--field-size` means nothing without `--field`. Another valid operation
    /// is given so the refusal cannot come from the no-operation check.
    func testApplyFieldSizeWithoutFieldIsAUsageError() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let output = dir.appendingPathComponent("o.docx")
        try makeForm(at: form)
        let result = try CLITestHelper.run([
            "word", "form", "apply", form.path, "--to-docx", output.path,
            "--checkbox-font", "標楷體", "--field-size", "12",
        ])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("--field-size 需要搭配 --field"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    /// The skipped-runs note names all three reasons and the count.
    func testApplyNotesSkippedCheckboxRunsWithTheirReasons() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let output = dir.appendingPathComponent("o.docx")
        let tracked = "<w:r><w:rPr><w:rPrChange w:id=\"8\" w:author=\"a\"><w:rPr/></w:rPrChange></w:rPr><w:t>A\u{25A1}B</w:t></w:r>"
        try makeForm(at: form, extraBody: paragraph("0000F00D", tracked))
        let result = try CLITestHelper.run([
            "word", "form", "apply", form.path, "--to-docx", output.path, "--checkbox-font", "標楷體",
        ])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stderr.contains("有 1 個含方框字元的 run 未改字型（另含其他內容、需要拆開但帶格式修訂，或在原生核取方塊內容控制項裡）"),
                      result.stderr)
    }

    /// A skipped cell cleanup is reported with the field id and the structure (#253).
    func testApplyNotesASkippedCellCleanup() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let output = dir.appendingPathComponent("o.docx")
        let cell = "<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w=\"3000\"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w=\"3000\" w:type=\"dxa\"/></w:tcPr>"
            + paragraph("0000F0D1", run("值"))
            + "<w:sdt><w:sdtPr/><w:sdtContent>" + paragraph("0000F0D2", run("控制項")) + "</w:sdtContent></w:sdt>"
            + "<w:p/></w:tc></w:tr></w:tbl><w:p/>"
        try makeForm(at: form, extraBody: cell)
        let result = try CLITestHelper.run([
            "word", "form", "apply", form.path, "--to-docx", output.path, "--field", "0000F0D1", "--field-size", "12",
        ])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stderr.contains("note: --field 0000F0D1 所在的儲存格含內容控制項（w:sdt），依規格不清除同格的空段落"),
                      result.stderr)
    }

    /// Removing half of a complex field is refused and writes nothing (#253).
    func testApplyRefusesSplittingAField() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let output = dir.appendingPathComponent("o.docx")
        let field = paragraph("0000F1D0", "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText> TOC </w:instrText></w:r>"
            + "<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>" + run("目錄"))
            + paragraph("0000F1D1", run("項目") + "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>")
        try makeForm(at: form, extraBody: field)
        let result = try CLITestHelper.run([
            "word", "form", "apply", form.path, "--to-docx", output.path, "--remove", "0000F1D0",
        ])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("0000F1D0") && result.stderr.contains("w:fldChar"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    /// #253 verify R5: the Markup Compatibility refusal reaches the terminal
    /// with a non-zero exit and no output written.
    func testApplyRefusesMovingAMarkerAcrossCompatibilityRules() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let output = dir.appendingPathComponent("o.docx")
        let body = "<w:p w14:paraId=\"0000C0A0\" xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\""
            + " mc:Ignorable=\"w14\"><w:bookmarkStart w:id=\"90\" w:name=\"c\"/>" + run("刪") + "</w:p>"
            + paragraph("0000C0A1", run("後") + "<w:bookmarkEnd w:id=\"90\"/>")
        try makeForm(at: form, extraBody: body)
        let result = try CLITestHelper.run([
            "word", "form", "apply", form.path, "--to-docx", output.path, "--remove", "0000C0A0",
        ])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("0000C0A0") && result.stderr.contains("Markup Compatibility"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
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

    /// The same numbering degradation is reported on the reverse path, so a
    /// list-checkbox slot does not lose its note without a trace.
    func testReverseNotesAnUnreadableNumberingPart() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let script = dir.appendingPathComponent("form.mdocx.swift")
        let broken = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<w:numbering xmlns:w=\"\(Self.w)\"><w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"0\">"
            + "<w:lvlText w:val=\"\u{25A1}\" w:val=\"%1.\"/></w:lvl></w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>"
        try makeForm(at: form, numberingOverride: broken)
        let result = try CLITestHelper.run([
            "word", "reverse", form.path, "--to-mdocx", script.path, "--slot", "choice=0000A0A0",
        ])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stderr.contains("word/numbering.xml 無法解析"), result.stderr)
    }

    // MARK: --remove-table and the body structure (#250)

    func testRemoveTableDeletesTheWholeTable() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let output = dir.appendingPathComponent("out.docx")
        try makeForm(at: form)
        let result = try CLITestHelper.run(["word", "form", "apply", form.path, "--to-docx", output.path,
                                            "--remove-table", "0000C0EE"])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let xml = try documentXML(output)
        XCTAssertFalse(xml.contains("<w:tbl>"), xml)
        XCTAssertTrue(xml.contains("0000B0D1") && xml.contains("0000A0A0"))
        XCTAssertFalse(result.stderr.contains("補一個空段落"), result.stderr)
    }

    func testRemovingTheParagraphBetweenTwoTablesIsRefused() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let output = dir.appendingPathComponent("out.docx")
        let second = "<w:tbl><w:tblPr/><w:tblGrid/><w:tr><w:tc>" + paragraph("0000D0D1", run("第二張")) + "</w:tc></w:tr></w:tbl>"
        try makeForm(at: form, extraBody: second)
        let result = try CLITestHelper.run(["word", "form", "apply", form.path, "--to-docx", output.path,
                                            "--remove", "0000A0A0"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("0000A0A0") && result.stderr.contains("緊鄰"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testABodyLeftEndingWithATableGetsAFinalParagraphAndANote() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let output = dir.appendingPathComponent("out.docx")
        try makeForm(at: form)
        let result = try CLITestHelper.run(["word", "form", "apply", form.path, "--to-docx", output.path,
                                            "--remove", "0000A0A0"])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stderr.contains("note: 刪除後本文會以表格"), result.stderr)
        XCTAssertTrue(try documentXML(output).contains("</w:tbl><w:p/><w:sectPr"))
    }

    func testRemoveTableOnAParagraphOutsideTablesIsRefused() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let output = dir.appendingPathComponent("out.docx")
        try makeForm(at: form)
        let result = try CLITestHelper.run(["word", "form", "apply", form.path, "--to-docx", output.path,
                                            "--remove-table", "0000B0D1"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("0000B0D1") && result.stderr.contains("不在表格裡"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    // MARK: --table-defaults and classify --grid (#250 requirement 1)

    private func cell(_ content: String, tcPr extra: String = "") -> String {
        "<w:tc><w:tcPr><w:tcW w:w=\"3000\" w:type=\"dxa\"/>\(extra)</w:tcPr>\(content)</w:tc>"
    }

    /// Two rows of a label column and a fill column, after the form's body.
    private var labelFillTable: String {
        let sized = "<w:rPr><w:sz w:val=\"20\"/></w:rPr>"
        return "<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w=\"3000\"/><w:gridCol w:w=\"3000\"/></w:tblGrid>"
            + "<w:tr>" + cell(paragraph("0000D001", run("姓名"))) + cell(paragraph("0000D002", run("王小明", rPr: sized)) + "<w:p/>") + "</w:tr>"
            + "<w:tr>" + cell(paragraph("0000D003", run("電話"))) + cell(paragraph("0000D004", run("0912", rPr: sized))) + "</w:tr>"
            + "</w:tbl><w:p/>"
    }

    func testApplyTableDefaultsTidiesTheNamedColumnOnly() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let output = dir.appendingPathComponent("o.docx")
        try makeForm(at: form, extraBody: labelFillTable)
        let result = try CLITestHelper.run([
            "word", "form", "apply", form.path, "--to-docx", output.path, "--table-defaults", "0000D001=col:2",
        ])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stderr.contains("填寫欄字級：10 pt"), result.stderr)
        XCTAssertTrue(result.stderr.contains("--table-defaults 0000D001：處理 2 個填寫欄儲存格"), result.stderr)
        let xml = try documentXML(output)
        for id in ["0000D002", "0000D004"] {
            XCTAssertTrue(xml.contains("<w:p w14:paraId=\"\(id)\"><w:pPr><w:jc w:val=\"left\"/>"), id)
        }
        XCTAssertTrue(xml.contains(paragraph("0000D001", run("姓名"))), "the label column is unchanged")
        XCTAssertTrue(xml.contains(paragraph("0000D003", run("電話"))), "the label column is unchanged")
    }

    func testApplyTableDefaultsNotesCellsOnlyPartlySelected() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let output = dir.appendingPathComponent("o.docx")
        let table = "<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w=\"3000\"/><w:gridCol w:w=\"3000\"/></w:tblGrid>"
            + "<w:tr>" + cell(paragraph("0000E001", run("申請表")), tcPr: "<w:gridSpan w:val=\"2\"/>") + "</w:tr>"
            + "<w:tr>" + cell(paragraph("0000E002", run("姓名"))) + cell(paragraph("0000E003", run("值"))) + "</w:tr>"
            + "</w:tbl><w:p/>"
        try makeForm(at: form, extraBody: table)
        let result = try CLITestHelper.run([
            "word", "form", "apply", form.path, "--to-docx", output.path,
            "--table-defaults", "0000E002=col:2", "--field-size", "12",
        ])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stderr.contains("note: --table-defaults 0000E002：r1c1-2 只有一部分在點名的欄列內，未處理"), result.stderr)
        XCTAssertTrue(try documentXML(output).contains("<w:sz w:val=\"24\"/>"), "--field-size applies to table fields")
    }

    func testApplyRefusesAMalformedTableDefaults() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let output = dir.appendingPathComponent("o.docx")
        try makeForm(at: form, extraBody: labelFillTable)
        let result = try CLITestHelper.run([
            "word", "form", "apply", form.path, "--to-docx", output.path, "--table-defaults", "0000D001=column:2",
        ])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("無效的 --table-defaults: 0000D001=column:2"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testApplyRefusesAColumnBeyondTheTable() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let output = dir.appendingPathComponent("o.docx")
        try makeForm(at: form, extraBody: labelFillTable)
        let result = try CLITestHelper.run([
            "word", "form", "apply", form.path, "--to-docx", output.path, "--table-defaults", "0000D001=col:3",
        ])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("點名了第 3 欄，但這張表只有 2 欄"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testClassifyGridAddsEachCellsPosition() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        try makeForm(at: form)
        let result = try CLITestHelper.run(["word", "form", "classify", "--grid", form.path])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(result.stdout.split(separator: "\n").map(String.init), [
            "0000B0D1\tbody\t-\t申請人資料",
            "0000C0DE\ttable-field\tt1:r1c1\t王小明",
            "0000C0EE\tcheckbox-line\tt1:r1c2\t)  \u{25A1}",
            "0000A0A0\tlist-checkbox\t-\t第一個選項",
        ])
    }

    func testClassifyGridMarksATableItCannotRead() throws {
        let dir = try tempDir()
        let form = dir.appendingPathComponent("form.docx")
        let table = "<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w=\"3000\"/></w:tblGrid><w:tr>"
            + cell(paragraph("0000E101", run("舊式合併")), tcPr: "<w:hMerge w:val=\"restart\"/>") + "</w:tr></w:tbl><w:p/>"
        try makeForm(at: form, extraBody: table)
        let result = try CLITestHelper.run(["word", "form", "classify", "--grid", form.path])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("0000E101\ttable-field\tt2:?\t舊式合併"), result.stdout)
        XCTAssertTrue(result.stderr.contains("note: 第 2 張表格的欄列位置無法判讀"), result.stderr)
    }
}
