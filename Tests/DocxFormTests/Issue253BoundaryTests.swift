// Issue253BoundaryTests.swift — boundaries of `word form apply` that used to
// pass silently or leave incomplete markup (macdoc#253): a skipped cell
// cleanup, the content-control size, what counts as an empty paragraph, and
// markup that pairs across the range `--remove` / `--truncate-from` deletes.

import XCTest
@testable import DocxForm

final class Issue253BoundaryTests: XCTestCase {
    private let sized = "<w:rPr><w:sz w:val=\"24\"/></w:rPr>"

    private func result(_ body: String, _ plan: FormPlan) throws -> FormResult {
        try plan.apply(toDocumentXML: TestXML.document(body))
    }

    private func apply(_ body: String, _ plan: FormPlan) throws -> String {
        TestXML.string(try result(body, plan).documentXML)
    }

    private func field(_ id: String) -> String {
        TestXML.paragraph(id, TestXML.run("值", rPr: sized))
    }

    // MARK: 1. A skipped cleanup is reported, with the structure that caused it

    func testSkippedCleanupIsReportedForAContentControl() throws {
        let wrapped = "<w:sdt><w:sdtPr/><w:sdtContent>" + TestXML.paragraph("0000F021", TestXML.run("控制項")) + "</w:sdtContent></w:sdt>"
        let out = try result(TestXML.table([TestXML.cell(field("0000F020") + wrapped + TestXML.paragraph("0000E020"))]),
                             FormPlan(fields: ["0000F020"]))
        XCTAssertEqual(out.skippedCleanups, [CleanupSkip(paragraphId: "0000F020", reasons: [.contentControl])])
        XCTAssertTrue(TestXML.string(out.documentXML).contains("0000E020"), "the skip itself is unchanged")
    }

    func testSkippedCleanupNamesEveryStructureInFixedOrder() throws {
        let nested = TestXML.table([TestXML.cell(TestXML.paragraph("0000N001", TestXML.run("內層")))])
        let custom = "<w:customXml w:element=\"x\">" + TestXML.paragraph("0000C001", TestXML.run("c")) + "</w:customXml>"
        let out = try result(TestXML.table([TestXML.cell(custom + field("0000F030") + nested + TestXML.paragraph(nil))]),
                             FormPlan(fields: ["0000F030"]))
        XCTAssertEqual(out.skippedCleanups, [CleanupSkip(paragraphId: "0000F030", reasons: [.nestedTable, .customXML])])
    }

    func testCleanupThatRunsReportsNothing() throws {
        let out = try result(TestXML.table([TestXML.cell(field("0000F040") + TestXML.paragraph("0000E040"))]),
                             FormPlan(fields: ["0000F040"]))
        XCTAssertEqual(out.skippedCleanups, [])
        XCTAssertFalse(TestXML.string(out.documentXML).contains("0000E040"))
    }

    // MARK: 1b. Content controls in the field paragraph get the field size

    func testContentControlRunPropertiesGetTheFieldSize() throws {
        let control = "<w:sdt><w:sdtPr><w:rPr><w:rFonts w:eastAsia=\"標楷體\"/><w:sz w:val=\"18\"/></w:rPr><w:dropDownList/></w:sdtPr>"
            + "<w:sdtContent>" + TestXML.run("選項一", rPr: "<w:rPr><w:sz w:val=\"18\"/></w:rPr>") + "</w:sdtContent></w:sdt>"
        let paragraph = TestXML.paragraph("0000F050", TestXML.run("類別：", rPr: sized) + control)
        let out = try apply(TestXML.table([TestXML.cell(paragraph)]),
                            FormPlan(fields: ["0000F050"], fieldSize: try FieldSize.parse(points: "12")))
        let index = try XMLTagIndex(out)
        let sdtPr = index.elements(named: "w:sdtPr").first!
        let rPr = index.child(of: sdtPr, named: "w:rPr")!
        XCTAssertEqual(index.children(of: rPr).map { index.tags[$0].name }, ["w:rFonts", "w:sz", "w:szCs"])
        XCTAssertTrue(index.elementString(rPr).contains("<w:sz w:val=\"24\"/><w:szCs w:val=\"24\"/>"))
    }

    func testContentControlWithoutRunPropertiesIsLeftWithout() throws {
        let control = "<w:sdt><w:sdtPr><w:dropDownList/></w:sdtPr><w:sdtContent>" + TestXML.run("選項一") + "</w:sdtContent></w:sdt>"
        let out = try apply(TestXML.table([TestXML.cell(TestXML.paragraph("0000F051", control))]),
                            FormPlan(fields: ["0000F051"], fieldSize: try FieldSize.parse(points: "12")))
        let index = try XMLTagIndex(out)
        XCTAssertNil(index.child(of: index.elements(named: "w:sdtPr").first!, named: "w:rPr"))
    }

    // MARK: 2. Numbering and paragraph-mark revisions are content

    func testNumberedEmptySiblingIsKept() throws {
        let numbered = TestXML.paragraph("0000E060", pPr: TestXML.numbered)
        let out = try apply(TestXML.table([TestXML.cell(field("0000F060") + numbered)]), FormPlan(fields: ["0000F060"]))
        XCTAssertTrue(out.contains("0000E060"), "a visible bullet is content")
    }

    func testNumberingIdZeroDoesNotMakeAParagraphNonEmpty() throws {
        let removed = TestXML.paragraph("0000E061", pPr: "<w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"0\"/></w:numPr></w:pPr>")
        let out = try apply(TestXML.table([TestXML.cell(field("0000F061") + removed)]), FormPlan(fields: ["0000F061"]))
        XCTAssertFalse(out.contains("0000E061"), "numId 0 removes the numbering, so nothing is shown")
    }

    func testNumberingWithoutAnIdIsContent() throws {
        let inherited = TestXML.paragraph("0000E062", pPr: "<w:pPr><w:numPr><w:ilvl w:val=\"1\"/></w:numPr></w:pPr>")
        let out = try apply(TestXML.table([TestXML.cell(field("0000F062") + inherited)]), FormPlan(fields: ["0000F062"]))
        XCTAssertTrue(out.contains("0000E062"), "the numbering id may come from the style")
    }

    func testParagraphMarkRevisionsAreContent() throws {
        let inserted = TestXML.paragraph("0000E063", pPr: "<w:pPr><w:rPr><w:ins w:id=\"5\" w:author=\"a\"/></w:rPr></w:pPr>")
        let changed = TestXML.paragraph("0000E064", pPr: "<w:pPr><w:jc w:val=\"left\"/><w:pPrChange w:id=\"6\" w:author=\"a\"><w:pPr/></w:pPrChange></w:pPr>")
        let formatted = TestXML.paragraph("0000E065", pPr: "<w:pPr><w:rPr><w:rPrChange w:id=\"7\" w:author=\"a\"><w:rPr/></w:rPrChange></w:rPr></w:pPr>")
        let out = try apply(TestXML.table([TestXML.cell(field("0000F063") + inserted + changed + formatted)]),
                            FormPlan(fields: ["0000F063"]))
        for kept in ["0000E063", "0000E064", "0000E065"] { XCTAssertTrue(out.contains(kept), kept) }
    }

    // MARK: 3a. Range markers whose partner stays are kept

    func testRemoveKeepsABookmarkStartWhoseEndStays() throws {
        let body = TestXML.paragraph("0000A001", TestXML.run("前"))
            + TestXML.paragraph("0000R001", "<w:bookmarkStart w:id=\"3\" w:name=\"b\"/>" + TestXML.run("刪"))
            + TestXML.paragraph("0000A002", TestXML.run("後") + "<w:bookmarkEnd w:id=\"3\"/>")
            + TestXML.bodySection
        let out = try apply(body, FormPlan(removals: ["0000R001"]))
        XCTAssertFalse(out.contains("0000R001"))
        XCTAssertFalse(out.contains("刪"))
        let start = try XCTUnwrap(out.range(of: "<w:bookmarkStart w:id=\"3\" w:name=\"b\"/>"))
        let next = try XCTUnwrap(out.range(of: "0000A002"))
        XCTAssertLessThan(start.lowerBound, next.lowerBound, "the start stays where the paragraph was")
        XCTAssertTrue(out.contains("<w:bookmarkEnd w:id=\"3\"/>"))
    }

    func testRemoveDropsMarkersPairedInsideTheParagraph() throws {
        let body = TestXML.paragraph("0000A010", TestXML.run("前"))
            + TestXML.paragraph("0000R010", "<w:bookmarkStart w:id=\"4\" w:name=\"c\"/>" + TestXML.run("刪") + "<w:bookmarkEnd w:id=\"4\"/>")
            + TestXML.bodySection
        let out = try apply(body, FormPlan(removals: ["0000R010"]))
        XCTAssertFalse(out.contains("w:bookmarkStart"))
        XCTAssertFalse(out.contains("w:bookmarkEnd"))
    }

    func testRemoveKeepsAMarkerWithoutAPartner() throws {
        let body = TestXML.paragraph("0000A020", TestXML.run("前"))
            + TestXML.paragraph("0000R020", "<w:permEnd w:id=\"9\"/>" + TestXML.run("刪"))
            + TestXML.bodySection
        let out = try apply(body, FormPlan(removals: ["0000R020"]))
        XCTAssertTrue(out.contains("<w:permEnd w:id=\"9\"/>"), "an unpaired marker is not ours to drop")
    }

    func testRemoveInACellKeepsTheMarkerInTheCell() throws {
        let cell = TestXML.paragraph("0000A030", TestXML.run("前"))
            + TestXML.paragraph("0000R030", "<w:commentRangeStart w:id=\"1\"/>" + TestXML.run("刪"))
            + TestXML.paragraph("0000A031", TestXML.run("後") + "<w:commentRangeEnd w:id=\"1\"/>"
                + "<w:r><w:commentReference w:id=\"1\"/></w:r>")
        let out = try apply(TestXML.table([TestXML.cell(cell)]) + TestXML.paragraph(nil) + TestXML.bodySection,
                            FormPlan(removals: ["0000R030"]))
        let index = try XMLTagIndex(out)
        let start = try XCTUnwrap(index.elements(named: "w:commentRangeStart").first)
        XCTAssertEqual(index.tags[index.tags[start].parent!].name, "w:tc")
    }

    func testTruncateKeepsAnEndWhoseStartIsKept() throws {
        let body = TestXML.paragraph("0000A040", "<w:bookmarkStart w:id=\"5\" w:name=\"d\"/>" + TestXML.run("留"))
            + TestXML.paragraph("0000T040", TestXML.run("刪") + "<w:bookmarkEnd w:id=\"5\"/>")
            + "<w:bookmarkStart w:id=\"6\" w:name=\"e\"/><w:bookmarkEnd w:id=\"6\"/>"
            + TestXML.bodySection
        let out = try apply(body, FormPlan(truncateFrom: "0000T040"))
        XCTAssertFalse(out.contains("刪"))
        XCTAssertTrue(out.contains("<w:bookmarkEnd w:id=\"5\"/><w:sectPr"), "the kept end sits before the final section")
        XCTAssertFalse(out.contains("w:id=\"6\""), "a range wholly in the cut goes with it")
    }

    func testTruncateFromTheStartOfASectionKeepsMarkersBeforeTheMovedSection() throws {
        let section = "<w:sectPr><w:pgSz w:w=\"16838\" w:h=\"11906\"/></w:sectPr>"
        let body = TestXML.paragraph("0000A050", "<w:moveFromRangeStart w:id=\"7\" w:name=\"m\"/>" + TestXML.run("留"))
            + TestXML.paragraph("0000A051", pPr: "<w:pPr>\(section)</w:pPr>", TestXML.run("節末"))
            + TestXML.paragraph("0000T050", TestXML.run("刪") + "<w:moveFromRangeEnd w:id=\"7\"/>")
            + TestXML.bodySection
        let out = try apply(body, FormPlan(truncateFrom: "0000T050"))
        XCTAssertTrue(out.contains("<w:moveFromRangeEnd w:id=\"7\"/>" + section + "</w:body>"))
    }

    // MARK: 3b. Fields and comment references that cannot move are refused

    func testRemoveRefusesSplittingAField() {
        let body = TestXML.paragraph("0000A060", TestXML.run("前"))
            + TestXML.paragraph("0000R060", "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText> TOC </w:instrText></w:r>"
                + "<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>" + TestXML.run("目錄"))
            + TestXML.paragraph("0000A061", TestXML.run("項目") + "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>")
            + TestXML.bodySection
        XCTAssertThrowsError(try apply(body, FormPlan(removals: ["0000R060"]))) {
            XCTAssertEqual($0 as? FormError, .splitsField("0000R060"))
        }
    }

    func testRemoveOfAWholeFieldIsAllowed() throws {
        let body = TestXML.paragraph("0000A070", TestXML.run("前"))
            + TestXML.paragraph("0000R070", "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText> PAGE </w:instrText></w:r>"
                + "<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>" + TestXML.run("1") + "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>")
            + TestXML.bodySection
        XCTAssertFalse(try apply(body, FormPlan(removals: ["0000R070"])).contains("w:fldChar"))
    }

    func testRemoveInsideAFieldResultIsAllowed() throws {
        let body = TestXML.paragraph("0000A080", "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText> TOC </w:instrText></w:r>"
                + "<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>" + TestXML.run("第一項"))
            + TestXML.paragraph("0000R080", TestXML.run("第二項"))
            + TestXML.paragraph("0000A081", TestXML.run("第三項") + "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>")
            + TestXML.bodySection
        let out = try apply(body, FormPlan(removals: ["0000R080"]))
        XCTAssertFalse(out.contains("第二項"))
        XCTAssertEqual(out.components(separatedBy: "w:fldChar ").count - 1, 3)
    }

    func testRemoveRefusesTakingACommentReferenceAwayFromItsRange() {
        let body = TestXML.paragraph("0000A090", "<w:commentRangeStart w:id=\"2\"/>" + TestXML.run("前") + "<w:commentRangeEnd w:id=\"2\"/>")
            + TestXML.paragraph("0000R090", "<w:r><w:commentReference w:id=\"2\"/></w:r>")
            + TestXML.bodySection
        XCTAssertThrowsError(try apply(body, FormPlan(removals: ["0000R090"]))) {
            XCTAssertEqual($0 as? FormError, .splitsComment("0000R090"))
        }
    }

    func testTruncateRefusesSplittingAField() {
        let body = TestXML.paragraph("0000A100", "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText> TOC </w:instrText></w:r>"
                + "<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>" + TestXML.run("目錄"))
            + TestXML.paragraph("0000T100", TestXML.run("項目") + "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>")
            + TestXML.bodySection
        XCTAssertThrowsError(try apply(body, FormPlan(truncateFrom: "0000T100"))) {
            XCTAssertEqual($0 as? FormError, .splitsField("0000T100"))
        }
    }

    func testTruncateRefusesTakingACommentReferenceAwayFromItsRange() {
        let body = TestXML.paragraph("0000A110", "<w:commentRangeStart w:id=\"3\"/>" + TestXML.run("留"))
            + TestXML.paragraph("0000T110", TestXML.run("刪") + "<w:commentRangeEnd w:id=\"3\"/><w:r><w:commentReference w:id=\"3\"/></w:r>")
            + TestXML.bodySection
        XCTAssertThrowsError(try apply(body, FormPlan(truncateFrom: "0000T110"))) {
            XCTAssertEqual($0 as? FormError, .splitsComment("0000T110"))
        }
    }

    func testTruncateOfAWholeCommentIsAllowed() throws {
        let body = TestXML.paragraph("0000A120", TestXML.run("留"))
            + TestXML.paragraph("0000T120", "<w:commentRangeStart w:id=\"4\"/>" + TestXML.run("刪")
                + "<w:commentRangeEnd w:id=\"4\"/><w:r><w:commentReference w:id=\"4\"/></w:r>")
            + TestXML.bodySection
        let out = try apply(body, FormPlan(truncateFrom: "0000T120"))
        XCTAssertFalse(out.contains("w:comment"))
    }

    func testRefusalMessagesSayWhatToDo() {
        XCTAssertTrue(FormError.splitsField("0000R060").description.contains("0000R060"))
        XCTAssertTrue(FormError.splitsField("0000R060").description.contains("w:fldChar"))
        XCTAssertTrue(FormError.splitsComment("0000R090").description.contains("w:commentReference"))
    }
}
