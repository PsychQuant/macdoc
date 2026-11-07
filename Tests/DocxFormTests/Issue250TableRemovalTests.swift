// Issue250TableRemovalTests.swift — removing a whole body-level table
// (`--remove-table`, macdoc#250) and the body structure every deletion keeps:
// two tables never become adjacent, the body keeps content and ends with a
// paragraph (one is added when a table would end it), and the last section
// keeps its content.

import XCTest
@testable import DocxForm

final class Issue250TableRemovalTests: XCTestCase {
    private func apply(_ body: String, _ plan: FormPlan) throws -> String {
        TestXML.string(try plan.apply(toDocumentXML: TestXML.document(body)).documentXML)
    }

    private func refusal(_ body: String, _ plan: FormPlan) -> FormError? {
        do {
            _ = try plan.apply(toDocumentXML: TestXML.document(body))
            return nil
        } catch {
            return error as? FormError
        }
    }

    private func p(_ id: String, _ text: String = "文字") -> String {
        TestXML.paragraph(id, TestXML.run(text))
    }

    private func table(_ ids: String...) -> String {
        TestXML.table(ids.map { TestXML.cell(p($0, "格\($0)")) })
    }

    private func bodyNames(_ xml: String) throws -> [String] {
        let index = try XMLTagIndex(xml)
        return index.children(of: index.elements(named: "w:body")[0]).map { index.tags[$0].name }
    }

    // MARK: removing a table

    func testTableNamedByAnyOfItsParagraphsIsRemoved() throws {
        let body = p("0000A001") + table("0000B001", "0000B002") + p("0000A002") + table("0000C001") + p("0000A003")
            + TestXML.bodySection
        let out = try apply(body, FormPlan(removedTables: ["0000B002"]))
        XCTAssertFalse(out.contains("0000B001"))
        XCTAssertFalse(out.contains("0000B002"))
        XCTAssertTrue(out.contains("0000C001"), "the other table stays")
        XCTAssertEqual(try bodyNames(out), ["w:p", "w:p", "w:tbl", "w:p", "w:sectPr"])
    }

    func testTwoParagraphsOfOneTableRemoveItOnce() throws {
        let body = p("0000A001") + table("0000B001", "0000B002") + p("0000A002") + TestXML.bodySection
        let out = try apply(body, FormPlan(removedTables: ["0000B001", "0000B002"]))
        XCTAssertEqual(try bodyNames(out), ["w:p", "w:p", "w:sectPr"])
    }

    func testTableInsideABodyLevelContentControlIsRemoved() throws {
        let wrapped = "<w:sdt><w:sdtPr/><w:sdtContent>" + table("0000B001") + "</w:sdtContent></w:sdt>"
        let out = try apply(p("0000A001") + wrapped + p("0000A002") + TestXML.bodySection,
                            FormPlan(removedTables: ["0000B001"]))
        XCTAssertFalse(out.contains("0000B001"))
        XCTAssertTrue(out.contains("0000A002"))
    }

    func testParagraphOutsideAnyTableIsRefused() {
        let body = p("0000A001") + table("0000B001") + p("0000A002") + TestXML.bodySection
        XCTAssertEqual(refusal(body, FormPlan(removedTables: ["0000A001"])), .notInTable("0000A001"))
    }

    func testParagraphInANestedTableIsRefused() {
        let nested = TestXML.table([TestXML.cell(p("0000N001"))])
        let body = p("0000A001") + TestXML.table([TestXML.cell(p("0000B001") + nested + TestXML.paragraph(nil))])
            + p("0000A002") + TestXML.bodySection
        XCTAssertEqual(refusal(body, FormPlan(removedTables: ["0000N001"])), .tableNotBodyLevel("0000N001"))
    }

    func testOtherOperationNamingAParagraphInTheTableIsRefused() {
        let body = p("0000A001") + table("0000B001", "0000B002") + p("0000A002") + TestXML.bodySection
        for plan in [FormPlan(fields: ["0000B002"], fieldSize: FieldSize(halfPoints: 24), removedTables: ["0000B001"]),
                     FormPlan(removals: ["0000B002"], removedTables: ["0000B001"]),
                     FormPlan(insertions: [FormInsertion(anchor: "0000B001", text: "x")], removedTables: ["0000B001"])] {
            guard case .conflictingOperations? = refusal(body, plan) else { return XCTFail("\(plan)") }
        }
    }

    func testTableInsideTheTruncatedRangeIsRefused() {
        let body = p("0000A001") + p("0000A002") + table("0000B001") + p("0000A003") + TestXML.bodySection
        guard case .conflictingOperations("0000B001", _)? = refusal(body, FormPlan(removedTables: ["0000B001"],
                                                                                      truncateFrom: "0000A002")) else {
            return XCTFail("table after the cut")
        }
    }

    func testBookmarkWithAPartnerOutsideKeepsTheMarkerAtBodyLevel() throws {
        let inside = TestXML.table([TestXML.cell(TestXML.paragraph("0000B001", "<w:bookmarkEnd w:id=\"7\"/>"
                                                                   + "<w:bookmarkStart w:id=\"8\" w:name=\"all\"/>"
                                                                   + TestXML.run("格") + "<w:bookmarkEnd w:id=\"8\"/>"))])
        let body = TestXML.paragraph("0000A001", "<w:bookmarkStart w:id=\"7\" w:name=\"cross\"/>" + TestXML.run("前"))
            + inside + p("0000A002") + TestXML.bodySection
        let out = try apply(body, FormPlan(removedTables: ["0000B001"]))
        XCTAssertTrue(out.contains("<w:bookmarkEnd w:id=\"7\"/>"), "partner kept outside, so the end stays")
        XCTAssertFalse(out.contains("w:id=\"8\""), "a bookmark wholly inside the table goes with it")
        XCTAssertEqual(try bodyNames(out), ["w:p", "w:bookmarkEnd", "w:p", "w:sectPr"])
    }

    func testFieldSplitAcrossTheTableIsRefused() {
        let begin = TestXML.paragraph("0000A001", "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r>")
        let inside = TestXML.table([TestXML.cell(TestXML.paragraph("0000B001", "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>"))])
        let body = begin + inside + p("0000A002") + TestXML.bodySection
        XCTAssertEqual(refusal(body, FormPlan(removedTables: ["0000B001"])), .splitsField("0000B001"))
    }

    // MARK: rule (a): two tables never become adjacent

    func testRemovingTheOnlyParagraphBetweenTwoTablesIsRefused() {
        let body = p("0000A001") + table("0000B001") + p("0000A002") + table("0000C001") + p("0000A003")
            + TestXML.bodySection
        XCTAssertEqual(refusal(body, FormPlan(removals: ["0000A002"])), .tablesWouldJoin(["0000A002"]))
    }

    func testRemovingATableAndTheParagraphBetweenTwoTablesIsRefused() {
        let body = p("0000A001") + table("0000B001") + table("0000X001") + p("0000A002") + table("0000C001")
            + p("0000A003") + TestXML.bodySection
        XCTAssertEqual(refusal(body, FormPlan(removals: ["0000A002"], removedTables: ["0000X001"])),
                       .tablesWouldJoin(["0000X001", "0000A002"]))
    }

    /// Tables that already touch are one table to Word; removing the middle
    /// one changes nothing about that, so it is allowed.
    func testRemovingATableBetweenTablesThatAlreadyTouchIsAllowed() throws {
        let body = p("0000A001") + table("0000B001") + table("0000X001") + table("0000C001") + p("0000A002")
            + TestXML.bodySection
        let out = try apply(body, FormPlan(removedTables: ["0000X001"]))
        XCTAssertEqual(try bodyNames(out), ["w:p", "w:tbl", "w:tbl", "w:p", "w:sectPr"])
    }

    func testRemovingATableBetweenParagraphsIsAllowed() throws {
        let body = table("0000B001") + p("0000A001") + table("0000X001") + p("0000A002") + table("0000C001")
            + p("0000A003") + TestXML.bodySection
        XCTAssertNoThrow(try apply(body, FormPlan(removedTables: ["0000X001"])))
    }

    // MARK: rule (b): the body keeps content and ends with a paragraph

    func testRemovingTheParagraphsAfterTheLastTableAddsAFinalParagraph() throws {
        let body = p("0000A001") + table("0000B001") + p("0000A002") + p("0000A003") + TestXML.bodySection
        let result = try FormPlan(removals: ["0000A002", "0000A003"]).apply(toDocumentXML: TestXML.document(body))
        let out = TestXML.string(result.documentXML)
        XCTAssertTrue(result.addedFinalParagraph)
        XCTAssertEqual(try bodyNames(out), ["w:p", "w:tbl", "w:p", "w:sectPr"])
        XCTAssertTrue(out.contains("</w:tbl><w:p/><w:sectPr"), out)
    }

    func testTruncatingRightAfterATableAddsAFinalParagraph() throws {
        let body = p("0000A001") + table("0000B001") + p("0000A002") + p("0000A003") + TestXML.bodySection
        let result = try FormPlan(truncateFrom: "0000A002").apply(toDocumentXML: TestXML.document(body))
        XCTAssertTrue(result.addedFinalParagraph)
        XCTAssertTrue(TestXML.string(result.documentXML).contains("</w:tbl><w:p/><w:sectPr"))
    }

    /// The added paragraph is the last block in both paths, after range
    /// markers the deletion keeps.
    func testAddedParagraphFollowsKeptMarkers() throws {
        let start = TestXML.paragraph("0000A001", "<w:bookmarkStart w:id=\"5\" w:name=\"m\"/>" + TestXML.run("前"))
        let end = TestXML.paragraph("0000A002", "<w:bookmarkEnd w:id=\"5\"/>" + TestXML.run("後"))
        let body = start + table("0000B001") + end + p("0000A003") + TestXML.bodySection
        for plan in [FormPlan(removals: ["0000A002", "0000A003"]), FormPlan(truncateFrom: "0000A002")] {
            let out = try apply(body, plan)
            XCTAssertTrue(out.contains("</w:tbl><w:bookmarkEnd w:id=\"5\"/><w:p/><w:sectPr"), "\(plan): \(out)")
        }
    }

    func testRemovingATableAtTheEndAddsNothing() throws {
        let body = p("0000A001") + table("0000B001") + p("0000A002") + TestXML.bodySection
        let result = try FormPlan(removedTables: ["0000B001"]).apply(toDocumentXML: TestXML.document(body))
        XCTAssertFalse(result.addedFinalParagraph)
        XCTAssertEqual(try bodyNames(TestXML.string(result.documentXML)), ["w:p", "w:p", "w:sectPr"])
    }

    func testRemovingEveryBodyBlockIsRefused() {
        let body = p("0000A001") + table("0000B001") + TestXML.paragraph("0000A002") + TestXML.bodySection
        XCTAssertEqual(refusal(body, FormPlan(removals: ["0000A001", "0000A002"], removedTables: ["0000B001"])),
                       .removalsLeaveEmptyBody(["0000A001", "0000B001", "0000A002"]))
    }

    /// A body that already ended with a table is not this command's doing.
    func testBodyThatAlreadyEndedWithATableGetsNoParagraph() throws {
        let body = p("0000A001") + p("0000A002") + table("0000B001") + TestXML.bodySection
        let result = try FormPlan(removals: ["0000A001"]).apply(toDocumentXML: TestXML.document(body))
        XCTAssertFalse(result.addedFinalParagraph)
        XCTAssertEqual(try bodyNames(TestXML.string(result.documentXML)), ["w:p", "w:tbl", "w:sectPr"])
    }

    // MARK: rule (c): the last section keeps content

    private let sectionBreak = "<w:pPr><w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/></w:sectPr></w:pPr>"

    func testRemovingEverythingAfterTheLastSectionBreakIsRefused() {
        let body = p("0000A001") + TestXML.paragraph("0000S001", pPr: sectionBreak, TestXML.run("節尾"))
            + table("0000B001") + p("0000A002") + TestXML.bodySection
        XCTAssertEqual(refusal(body, FormPlan(removals: ["0000A002"], removedTables: ["0000B001"])),
                       .lastSectionWouldBeEmpty(["0000B001", "0000A002"]))
    }

    func testRemovingATableBeforeTheLastSectionBreakIsAllowed() throws {
        let body = p("0000A001") + table("0000B001") + TestXML.paragraph("0000S001", pPr: sectionBreak, TestXML.run("節尾"))
            + p("0000A002") + TestXML.bodySection
        let out = try apply(body, FormPlan(removedTables: ["0000B001"]))
        XCTAssertTrue(out.contains("0000S001"), "the section break after the table stays")
    }

    /// Truncation folds such a break into the final section itself (#249), so
    /// rule (c) does not apply to it.
    func testTruncationAfterASectionBreakIsStillAllowed() throws {
        let body = p("0000A001") + TestXML.paragraph("0000S001", pPr: sectionBreak, TestXML.run("節尾"))
            + p("0000A002") + p("0000A003") + TestXML.bodySection
        XCTAssertNoThrow(try apply(body, FormPlan(truncateFrom: "0000A002")))
    }

    // MARK: plan and messages

    func testRemovedTablesCountAsAnOperationAndAsNamedIds() {
        let plan = FormPlan(removedTables: ["0000B001", "0000B001"])
        XCTAssertTrue(plan.hasOperations)
        XCTAssertEqual(plan.namedIds, ["0000B001"])
    }

    func testMessagesNameTheParagraphs() {
        XCTAssertTrue(FormError.notInTable("0000A001").description.contains("0000A001"))
        XCTAssertTrue(FormError.tableNotBodyLevel("0000N001").description.contains("0000N001"))
        XCTAssertTrue(FormError.tablesWouldJoin(["0000A002"]).description.contains("0000A002"))
        XCTAssertTrue(FormError.removalsLeaveEmptyBody(["0000A002", "0000A003"]).description.contains("0000A002、0000A003"))
        XCTAssertTrue(FormError.lastSectionWouldBeEmpty(["0000B001"]).description.contains("0000B001"))
    }

    // MARK: verify round 1

    private func textBox(_ inner: String) -> String {
        "<w:r><w:drawing><wp:inline><w:txbxContent>" + inner + "</w:txbxContent></wp:inline></w:drawing></w:r>"
    }

    /// A text box is its own story: naming a paragraph in it never reaches the
    /// table around the text box.
    func testParagraphInATextBoxInsideATableCellIsRefused() {
        let cell = TestXML.paragraph("0000B001", TestXML.run("格") + textBox(p("0000K001", "方塊")))
        let body = p("0000A001") + TestXML.table([TestXML.cell(cell)]) + p("0000A002") + TestXML.bodySection
        XCTAssertEqual(refusal(body, FormPlan(removedTables: ["0000K001"])), .inTextBox("0000K001"))
    }

    func testParagraphInATextBoxOutsideAnyTableIsNotInATable() {
        let body = TestXML.paragraph("0000A001", textBox(p("0000K003", "方塊"))) + p("0000A002") + TestXML.bodySection
        XCTAssertEqual(refusal(body, FormPlan(removedTables: ["0000K003"])), .notInTable("0000K003"))
    }

    func testTableInsideATextBoxIsRefused() {
        let boxed = TestXML.paragraph("0000A001", textBox(table("0000K002") + TestXML.paragraph(nil)))
        let body = boxed + p("0000A002") + TestXML.bodySection
        XCTAssertEqual(refusal(body, FormPlan(removedTables: ["0000K002"])), .tableNotBodyLevel("0000K002"))
    }

    func testTableHoldingASectionBreakIsRefused() {
        let broken = TestXML.paragraph("0000B002", pPr: sectionBreak, TestXML.run("格"))
        let body = p("0000A001") + TestXML.table([TestXML.cell(p("0000B001") + broken)]) + p("0000A002")
            + TestXML.bodySection
        XCTAssertEqual(refusal(body, FormPlan(removedTables: ["0000B001"])), .tableCarriesSectionBreak("0000B001"))
    }

    func testCommentReferenceInsideWithItsRangeOutsideIsRefused() {
        let range = TestXML.paragraph("0000A001", "<w:commentRangeStart w:id=\"3\"/>" + TestXML.run("註")
                                      + "<w:commentRangeEnd w:id=\"3\"/>")
        let inside = TestXML.table([TestXML.cell(TestXML.paragraph("0000B001", "<w:r><w:commentReference w:id=\"3\"/></w:r>"))])
        let body = range + inside + p("0000A002") + TestXML.bodySection
        XCTAssertEqual(refusal(body, FormPlan(removedTables: ["0000B001"])), .splitsComment("0000B001"))
    }

    func testKeptMarkerUnderCompatibilityRulesInTheTableIsRefused() {
        let mc = "http://schemas.openxmlformats.org/markup-compatibility/2006"
        let inside = "<w:tbl xmlns:mc=\"\(mc)\" mc:Ignorable=\"w14\"><w:tblPr/><w:tblGrid/><w:tr><w:tc>"
            + TestXML.paragraph("0000B001", "<w:bookmarkEnd w:id=\"9\"/>" + TestXML.run("格")) + "</w:tc></w:tr></w:tbl>"
        let body = TestXML.paragraph("0000A001", "<w:bookmarkStart w:id=\"9\" w:name=\"x\"/>" + TestXML.run("前"))
            + inside + p("0000A002") + TestXML.bodySection
        XCTAssertEqual(refusal(body, FormPlan(removedTables: ["0000B001"])), .markerUnderCompatibilityRules("0000B001"))
    }

    func testRemovedTableAndTheCutLeavingNothingBeforeIsRefused() {
        let body = table("0000B001") + p("0000A001") + p("0000A002") + TestXML.bodySection
        XCTAssertEqual(refusal(body, FormPlan(removedTables: ["0000B001"], truncateFrom: "0000A001")),
                       .removalsLeaveNothingBeforeCut("0000A001"))
    }

    func testPartWithTwoBodiesIsRefusedWhenDeleting() {
        let xml = Array(("<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:document \(TestXML.namespaces)><w:body>"
            + p("0000A001") + table("0000B001") + p("0000A002") + "</w:body><w:body>" + p("0000A003")
            + "</w:body></w:document>").utf8)
        XCTAssertThrowsError(try FormPlan(removedTables: ["0000B001"]).apply(toDocumentXML: xml)) {
            guard case .malformedPart(let detail)? = $0 as? FormError else { return XCTFail("\($0)") }
            XCTAssertTrue(detail.contains("多個 w:body"), detail)
        }
        // A plan that deletes nothing still applies to such a part.
        XCTAssertNoThrow(try FormPlan(checkboxFont: "標楷體").apply(toDocumentXML: xml))
    }

    /// The content control around a removed table stays, now empty
    /// (documented in SKILL.md).
    func testContentControlAroundARemovedTableIsLeftEmpty() throws {
        let wrapped = "<w:sdt><w:sdtPr/><w:sdtContent>" + table("0000B001") + "</w:sdtContent></w:sdt>"
        let out = try apply(p("0000A001") + wrapped + p("0000A002") + TestXML.bodySection,
                            FormPlan(removedTables: ["0000B001"]))
        XCTAssertTrue(out.contains("<w:sdtContent></w:sdtContent>"), out)
    }

    func testTextBoxMessageNamesTheParagraph() {
        XCTAssertTrue(FormError.inTextBox("0000K001").description.contains("0000K001"))
        XCTAssertTrue(FormError.tableCarriesSectionBreak("0000B001").description.contains("0000B001"))
        XCTAssertTrue(FormError.tablesWouldJoin(["0000A002"]).description.contains("--remove-table"))
    }
}
