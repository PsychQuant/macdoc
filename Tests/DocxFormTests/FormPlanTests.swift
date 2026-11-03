// FormPlanTests.swift — "Apply is all-or-nothing" (#249).

import XCTest
@testable import DocxForm

final class FormPlanTests: XCTestCase {
    func testOneBadIdAmongSeveralProducesNoResult() {
        let field = TestXML.paragraph("0000F001", TestXML.run("值", rPr: "<w:rPr><w:sz w:val=\"24\"/></w:rPr>"))
        let body = TestXML.table([TestXML.cell(field)])
        let plan = FormPlan(fields: ["0000F001"], removals: ["DEADBEEF"])
        XCTAssertThrowsError(try plan.apply(toDocumentXML: TestXML.document(body))) {
            XCTAssertEqual($0 as? FormError, .paragraphNotFound("DEADBEEF"))
        }
    }

    func testIdOnATableRowIsNotAParagraph() {
        let body = "<w:tbl><w:tr w14:paraId=\"0000AAAA\">" + TestXML.cell(TestXML.paragraph(nil, TestXML.run("x"))) + "</w:tr></w:tbl>"
        XCTAssertThrowsError(try FormPlan(removals: ["0000AAAA"]).apply(toDocumentXML: TestXML.document(body))) {
            XCTAssertEqual($0 as? FormError, .notOnParagraph("0000AAAA", carrier: "w:tr"))
        }
    }

    func testDuplicateParaIdIsAmbiguous() {
        let body = TestXML.paragraph("0000BBBB", TestXML.run("a")) + TestXML.paragraph("0000BBBB", TestXML.run("b"))
        XCTAssertThrowsError(try FormPlan(removals: ["0000BBBB"]).apply(toDocumentXML: TestXML.document(body))) {
            XCTAssertEqual($0 as? FormError, .paragraphAmbiguous("0000BBBB", count: 2))
        }
    }

    /// Removing F is legal against the original cell (F and an empty E), but
    /// field normalization of F removes E first; the remove step must then
    /// refuse instead of emptying the cell.
    func testRemoveThatBecomesIllegalAfterFieldNormalization() {
        let field = TestXML.paragraph("0000F002", TestXML.run("值", rPr: "<w:rPr><w:sz w:val=\"24\"/></w:rPr>"))
        let empty = TestXML.paragraph("0000E002")
        let body = TestXML.table([TestXML.cell(field + empty)])
        let plan = FormPlan(fields: ["0000F002"], removals: ["0000F002"])
        XCTAssertThrowsError(try plan.apply(toDocumentXML: TestXML.document(body))) {
            XCTAssertEqual($0 as? FormError, .onlyParagraphInCell("0000F002"))
        }
    }

    /// A paragraph the plan names is never removed by the empty-sibling cleanup.
    func testNamedEmptyParagraphIsProtectedFromCleanup() throws {
        let field = TestXML.paragraph("0000F003", TestXML.run("值", rPr: "<w:rPr><w:sz w:val=\"24\"/></w:rPr>"))
        let anchor = TestXML.paragraph("0000E003")
        let body = TestXML.table([TestXML.cell(field + anchor)])
        let plan = FormPlan(fields: ["0000F003"], insertions: [FormInsertion(anchor: "0000E003", text: "補充")])
        let out = try plan.apply(toDocumentXML: TestXML.document(body)).documentXML
        XCTAssertTrue(TestXML.string(out).contains("0000E003"))
        XCTAssertTrue(TestXML.string(out).contains("補充"))
    }

    /// Fixed order: the ■ added by tick-list is re-fonted by checkbox-font.
    func testTickRunIsRefontedBecauseCheckboxFontRunsAfterIt() throws {
        let body = TestXML.paragraph("0000T001", pPr: TestXML.numbered, TestXML.run("選項"))
        let plan = FormPlan(checkboxFont: "標楷體", tickList: ["0000T001"])
        let out = try plan.apply(toDocumentXML: TestXML.document(body)).documentXML
        let paragraph = try TestXML.paragraphXML("0000T001", in: out)
        XCTAssertTrue(paragraph.contains("<w:r><w:rPr><w:rFonts w:ascii=\"標楷體\" w:hAnsi=\"標楷體\" w:eastAsia=\"標楷體\" w:cs=\"標楷體\"/></w:rPr><w:t>\u{25A0}</w:t></w:r>"))
    }

    /// Fixed order: an inserted paragraph copies the anchor after field normalization.
    func testInsertCopiesTheNormalizedFieldFormat() throws {
        let pPr = "<w:pPr><w:ind w:firstLine=\"480\"/></w:pPr>"
        let field = TestXML.paragraph("0000F004", pPr: pPr, TestXML.run("第一行", rPr: "<w:rPr><w:sz w:val=\"18\"/></w:rPr>"))
        let body = TestXML.table([TestXML.cell(field)])
        let plan = FormPlan(fields: ["0000F004"], fieldSize: FieldSize(halfPoints: 24),
                            insertions: [FormInsertion(anchor: "0000F004", text: "第二行")])
        let out = try plan.apply(toDocumentXML: TestXML.document(body)).documentXML
        let index = try XMLTagIndex(out)
        let inserted = index.elements(named: "w:p")[1]
        let xml = index.elementString(inserted)
        XCTAssertFalse(xml.contains("w:ind"))
        XCTAssertTrue(xml.contains("<w:jc w:val=\"left\"/>"))
        XCTAssertTrue(xml.contains("<w:sz w:val=\"24\"/>"))
    }

    func testDuplicateIdsAreAppliedOnce() throws {
        let body = TestXML.paragraph("0000R001", TestXML.run("刪")) + TestXML.paragraph("0000R002", TestXML.run("留"))
        let out = try FormPlan(removals: ["0000R001", "0000R001"]).apply(toDocumentXML: TestXML.document(body)).documentXML
        XCTAssertFalse(TestXML.string(out).contains("0000R001"))
    }

    func testEmptyPlanHasNoOperations() {
        XCTAssertFalse(FormPlan().hasOperations)
        XCTAssertTrue(FormPlan(truncateFrom: "x").hasOperations)
    }

    func testMalformedInputIsReported() {
        XCTAssertThrowsError(try FormPlan(removals: ["x"]).apply(toDocumentXML: Array("<w:document><w:body>".utf8))) {
            guard case .malformedPart = $0 as? FormError else { return XCTFail("\($0)") }
        }
    }
}
