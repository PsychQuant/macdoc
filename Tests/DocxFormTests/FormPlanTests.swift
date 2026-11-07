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

    /// Each removal is legal against the original two-paragraph cell on its
    /// own, but together they would empty it. The removals are judged as one
    /// set (#253 verify R2), and the refusal names both paragraphs, since
    /// neither is the cell's only paragraph.
    func testRemovalsThatTogetherEmptyACellAreRefusedNamingBoth() {
        let body = TestXML.table([TestXML.cell(TestXML.paragraph("0000R020", TestXML.run("一"))
                                               + TestXML.paragraph("0000R021", TestXML.run("二")))])
        let plan = FormPlan(removals: ["0000R021", "0000R020"])
        XCTAssertThrowsError(try plan.apply(toDocumentXML: TestXML.document(body))) {
            XCTAssertEqual($0 as? FormError, .removalsLeaveNoParagraph(["0000R020", "0000R021"]))
        }
    }

    func testRemovedParagraphNamedByAnotherOperationIsAConflict() {
        let body = TestXML.paragraph("0000K001", TestXML.run("錨點")) + TestXML.paragraph("0000K002", TestXML.run("後"))
        let plan = FormPlan(insertions: [FormInsertion(anchor: "0000K001", text: "新")], removals: ["0000K001"])
        XCTAssertThrowsError(try plan.apply(toDocumentXML: TestXML.document(body))) {
            guard case .conflictingOperations("0000K001", _) = $0 as? FormError else { return XCTFail("\($0)") }
        }
    }

    func testNamedParagraphInsideTheTruncatedRangeIsAConflict() {
        let body = TestXML.paragraph("0000K010", TestXML.run("留"))
            + TestXML.paragraph("0000K011", TestXML.run("切點"))
            + TestXML.paragraph("0000K012", TestXML.run("被切掉")) + TestXML.bodySection
        let plan = FormPlan(insertions: [FormInsertion(anchor: "0000K012", text: "新")], truncateFrom: "0000K011")
        XCTAssertThrowsError(try plan.apply(toDocumentXML: TestXML.document(body))) {
            guard case .conflictingOperations("0000K012", _) = $0 as? FormError else { return XCTFail("\($0)") }
        }
        let selfCut = FormPlan(insertions: [FormInsertion(anchor: "0000K011", text: "新")], truncateFrom: "0000K011")
        XCTAssertThrowsError(try selfCut.apply(toDocumentXML: TestXML.document(body))) {
            guard case .conflictingOperations("0000K011", _) = $0 as? FormError else { return XCTFail("\($0)") }
        }
    }

    /// A paragraph in a text box lives inside its outer paragraph's element:
    /// removing the outer one would silently take the inner one with it.
    func testNamedParagraphNestedInsideARemovedParagraphIsAConflict() {
        let textBox = "<w:r><w:drawing><wp:inline><w:txbxContent>"
            + TestXML.paragraph("0000K021", TestXML.run("文字方塊")) + "</w:txbxContent></wp:inline></w:drawing></w:r>"
        let body = TestXML.paragraph("0000K020", TestXML.run("外層") + textBox) + TestXML.paragraph("0000K022", TestXML.run("後"))
        let insert = FormPlan(insertions: [FormInsertion(anchor: "0000K021", text: "新")], removals: ["0000K020"])
        XCTAssertThrowsError(try insert.apply(toDocumentXML: TestXML.document(body))) {
            guard case .conflictingOperations("0000K021", _) = $0 as? FormError else { return XCTFail("\($0)") }
        }
        let nestedRemoval = FormPlan(removals: ["0000K020", "0000K021"])
        XCTAssertThrowsError(try nestedRemoval.apply(toDocumentXML: TestXML.document(body))) {
            guard case .conflictingOperations("0000K021", _) = $0 as? FormError else { return XCTFail("\($0)") }
        }
    }

    func testOverlappingEditsThrowInsteadOfTrapping() throws {
        var editor = try XMLEditor(Array("<a><b/></a>".utf8))
        XCTAssertThrowsError(try editor.apply([.replace(0..<6, with: "x"), .replace(3..<7, with: "y")])) {
            guard case .malformedResult = $0 as? FormError else { return XCTFail("\($0)") }
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
