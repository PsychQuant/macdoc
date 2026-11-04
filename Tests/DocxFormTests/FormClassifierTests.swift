// FormClassifierTests.swift — "Paragraph kinds are assigned by structure
// from a closed enumeration" and the classify listing (#249).

import XCTest
@testable import DocxForm

final class FormClassifierTests: XCTestCase {
    /// The spec's kind table, row by row.
    func testKindTable() throws {
        let body = TestXML.paragraph("00000001", TestXML.run("申請人資料如下"))
            + TestXML.table([
                TestXML.cell(TestXML.paragraph("00000002", TestXML.run("王小明"))),
                TestXML.cell(TestXML.paragraph("00000003", TestXML.run("\u{25A1} 是　\u{25A1} 否"))),
            ])
            + TestXML.paragraph("00000004", pPr: TestXML.numbered, TestXML.run("第一個選項"))
            + TestXML.paragraph("00000005", TestXML.run("說明：請勿填寫本欄"))
        let result = try FormClassifier.classify(documentXML: TestXML.document(body),
                                                 numberingXML: TestXML.numbering())
        XCTAssertEqual(result.map(\.paraId), ["00000001", "00000002", "00000003", "00000004", "00000005"])
        XCTAssertEqual(result.map(\.kind), [.body, .tableField, .checkboxLine, .listCheckbox, .body])
        XCTAssertEqual(result[1].text, "王小明")
    }

    func testNumberingInsidePropertyChangeIsNotTheParagraphsOwn() throws {
        let pPr = "<w:pPr><w:pPrChange w:id=\"1\"><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"3\"/></w:numPr></w:pPr></w:pPrChange></w:pPr>"
        let body = TestXML.paragraph("00000001", pPr: pPr, TestXML.run("選項"))
        let result = try FormClassifier.classify(documentXML: TestXML.document(body), numberingXML: TestXML.numbering())
        XCTAssertEqual(result.map(\.kind), [.body])
    }

    func testNumberingWhoseLevelTextIsNotABox() throws {
        let pPr = "<w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"4\"/></w:numPr></w:pPr>"
        let body = TestXML.paragraph("00000001", pPr: pPr, TestXML.run("一般清單"))
        let result = try FormClassifier.classify(documentXML: TestXML.document(body), numberingXML: TestXML.numbering())
        XCTAssertEqual(result.map(\.kind), [.body])
    }

    func testNumberingIdZeroMeansNoNumbering() throws {
        let pPr = "<w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"0\"/></w:numPr></w:pPr>"
        let body = TestXML.paragraph("00000001", pPr: pPr, TestXML.run("沒有編號"))
        let result = try FormClassifier.classify(documentXML: TestXML.document(body), numberingXML: TestXML.numbering())
        XCTAssertEqual(result.map(\.kind), [.body])
    }

    func testLevelOverrideTextWins() throws {
        let numbering = Array(("<w:numbering xmlns:w=\"x\">"
            + "<w:abstractNum w:abstractNumId=\"8\"><w:lvl w:ilvl=\"0\"><w:lvlText w:val=\"%1.\"/></w:lvl></w:abstractNum>"
            + "<w:num w:numId=\"9\"><w:abstractNumId w:val=\"8\"/><w:lvlOverride w:ilvl=\"0\"><w:lvl w:ilvl=\"0\"><w:lvlText w:val=\"\u{2610}\"/></w:lvl></w:lvlOverride></w:num>"
            + "</w:numbering>").utf8)
        let pPr = "<w:pPr><w:numPr><w:numId w:val=\"9\"/></w:numPr></w:pPr>"
        let body = TestXML.paragraph("00000001", pPr: pPr, TestXML.run("選項"))
        let result = try FormClassifier.classify(documentXML: TestXML.document(body), numberingXML: numbering)
        XCTAssertEqual(result.map(\.kind), [.listCheckbox])
    }

    func testWithoutNumberingPartABoxBulletCannotBeSeen() throws {
        let body = TestXML.paragraph("00000001", pPr: TestXML.numbered, TestXML.run("選項"))
        let result = try FormClassifier.classify(documentXML: TestXML.document(body), numberingXML: nil)
        XCTAssertEqual(result.map(\.kind), [.body])
    }

    func testMalformedNumberingOnlyDisablesListDetection() throws {
        let body = TestXML.table([TestXML.cell(TestXML.paragraph("0000M001", TestXML.run("值")))])
            + TestXML.paragraph("0000M002", pPr: TestXML.numbered, TestXML.run("選項"))
        let broken = Array("<w:numbering><w:num>".utf8)
        XCTAssertFalse(FormClassifier.isReadableNumbering(broken))
        let result = try FormClassifier.classify(documentXML: TestXML.document(body), numberingXML: broken)
        XCTAssertEqual(result.map(\.kind), [.tableField, .body])
    }

    /// Balanced tags are not enough: a part an XML parser rejects (here a
    /// duplicate attribute) is unreadable too.
    func testNumberingThatIsNotWellFormedXMLIsUnreadable() throws {
        let body = TestXML.paragraph("0000M003", pPr: TestXML.numbered, TestXML.run("選項"))
        let duplicate = TestXML.string(TestXML.numbering())
            .replacingOccurrences(of: "<w:lvlText w:val=\"\u{25A1}\"/>", with: "<w:lvlText w:val=\"\u{25A1}\" w:val=\"%1.\"/>")
        XCTAssertFalse(FormClassifier.isReadableNumbering(Array(duplicate.utf8)))
        let result = try FormClassifier.classify(documentXML: TestXML.document(body), numberingXML: Array(duplicate.utf8))
        XCTAssertEqual(result.map(\.kind), [.body])
    }

    /// A DOCTYPE is refused before any XML parser sees the part.
    func testNumberingWithADoctypeIsUnreadable() {
        let withDoctype = "<?xml version=\"1.0\"?><!DOCTYPE n [<!ENTITY e \"x\">]>"
            + TestXML.string(TestXML.numbering()).replacingOccurrences(of: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>", with: "")
        XCTAssertFalse(FormClassifier.isReadableNumbering(Array(withDoctype.utf8)))
    }

    /// A paragraph in a text box anchored in a cell belongs to the text box.
    func testTextBoxParagraphInsideACellIsNotATableField() throws {
        let textBox = "<w:r><w:drawing><wp:inline><w:txbxContent>"
            + TestXML.paragraph("000000C2", TestXML.run("方塊內")) + "</w:txbxContent></wp:inline></w:drawing></w:r>"
        let body = TestXML.table([TestXML.cell(TestXML.paragraph("000000C1", TestXML.run("格內") + textBox))])
        let result = try FormClassifier.classify(documentXML: TestXML.document(body), numberingXML: nil)
        XCTAssertEqual(result.map(\.kind), [.tableField, .body])
    }

    func testParagraphsWithoutParaIdAreNotListed() throws {
        let body = TestXML.paragraph(nil, TestXML.run("沒有 id")) + TestXML.paragraph("0000000A", TestXML.run("有 id"))
        let result = try FormClassifier.classify(documentXML: TestXML.document(body), numberingXML: nil)
        XCTAssertEqual(result.map(\.paraId), ["0000000A"])
    }

    func testTextBoxTextBelongsToItsOwnParagraph() throws {
        let textBox = "<w:r><w:drawing><wp:inline><w:txbxContent>"
            + TestXML.paragraph("000000B2", TestXML.run("\u{25A1} 方框")) + "</w:txbxContent></wp:inline></w:drawing></w:r>"
        let body = TestXML.paragraph("000000B1", TestXML.run("外層") + textBox)
        let result = try FormClassifier.classify(documentXML: TestXML.document(body), numberingXML: nil)
        XCTAssertEqual(result.first { $0.paraId == "000000B1" }?.kind, .body)
        XCTAssertEqual(result.first { $0.paraId == "000000B1" }?.text, "外層")
        XCTAssertEqual(result.first { $0.paraId == "000000B2" }?.kind, .checkboxLine)
    }

    func testOnlyTheFiveBoxGlyphsCount() {
        for glyph in ["\u{25A1}", "\u{25A0}", "\u{2610}", "\u{2611}", "\u{2612}"] {
            XCTAssertTrue(FormClassifier.containsBoxGlyph("x\(glyph)"), glyph)
        }
        for other in ["\u{25A2}", "\u{25CB}", "\u{F0A8}", "[ ]"] {
            XCTAssertFalse(FormClassifier.containsBoxGlyph(other), other)
        }
    }
}
