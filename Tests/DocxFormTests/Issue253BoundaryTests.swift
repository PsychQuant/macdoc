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

    // MARK: verify round 1 (#253)

    private let begin = "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText> TOC </w:instrText></w:r>"
    private let separate = "<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>"
    private let end = "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>"

    /// R1 #1: the separator is part of the field, not of its result.
    func testRemovingOnlyTheSeparatorParagraphIsRefused() {
        let body = TestXML.paragraph("0000A200", begin)
            + TestXML.paragraph("0000R200", separate + TestXML.run("第一項"))
            + TestXML.paragraph("0000A201", TestXML.run("第二項") + end)
            + TestXML.bodySection
        XCTAssertThrowsError(try apply(body, FormPlan(removals: ["0000R200"]))) {
            XCTAssertEqual($0 as? FormError, .splitsField("0000R200"))
        }
    }

    /// R1 #2: naming every paragraph of a field removes it whole.
    func testRemovingEveryParagraphOfAFieldIsAllowed() throws {
        let body = TestXML.paragraph("0000A210", TestXML.run("留"))
            + TestXML.paragraph("0000R210", begin + separate + TestXML.run("第一項"))
            + TestXML.paragraph("0000R211", TestXML.run("第二項") + end)
            + TestXML.bodySection
        let out = try apply(body, FormPlan(removals: ["0000R210", "0000R211"]))
        XCTAssertFalse(out.contains("w:fldChar"))
        XCTAssertTrue(out.contains("0000A210"))
    }

    func testRemovingACommentReferenceWithItsRangeIsAllowed() throws {
        let body = TestXML.paragraph("0000A220", TestXML.run("留"))
            + TestXML.paragraph("0000R220", "<w:commentRangeStart w:id=\"5\"/>" + TestXML.run("刪") + "<w:commentRangeEnd w:id=\"5\"/>")
            + TestXML.paragraph("0000R221", "<w:r><w:commentReference w:id=\"5\"/></w:r>")
            + TestXML.bodySection
        let out = try apply(body, FormPlan(removals: ["0000R220", "0000R221"]))
        XCTAssertFalse(out.contains("w:comment"))
    }

    func testRemovingAParagraphAndTruncatingItsRangePartnerIsAllowed() throws {
        let body = TestXML.paragraph("0000A230", TestXML.run("留"))
            + TestXML.paragraph("0000R230", begin + separate + TestXML.run("目錄"))
            + TestXML.paragraph("0000A231", TestXML.run("中間"))
            + TestXML.paragraph("0000T230", TestXML.run("項目") + end)
            + TestXML.bodySection
        let out = try apply(body, FormPlan(removals: ["0000R230"], truncateFrom: "0000T230"))
        XCTAssertFalse(out.contains("w:fldChar"))
    }

    /// R1 #5: both halves named together go together.
    func testBookmarkHalvesRemovedTogetherAreBothDropped() throws {
        let body = TestXML.paragraph("0000A240", TestXML.run("留"))
            + TestXML.paragraph("0000R240", "<w:bookmarkStart w:id=\"11\" w:name=\"h\"/>" + TestXML.run("一"))
            + TestXML.paragraph("0000R241", TestXML.run("二") + "<w:bookmarkEnd w:id=\"11\"/>")
            + TestXML.bodySection
        let out = try apply(body, FormPlan(removals: ["0000R240", "0000R241"]))
        XCTAssertFalse(out.contains("w:bookmark"))
    }

    /// R1 #3: a cell keeps ending with a paragraph.
    func testRemovingTheLastParagraphOfACellPutsKeptMarkersInThePreviousParagraph() throws {
        let cell = TestXML.paragraph("0000A250", TestXML.run("前"))
            + TestXML.paragraph("0000R250", "<w:bookmarkStart w:id=\"12\" w:name=\"k\"/>" + TestXML.run("刪"))
        let body = TestXML.table([TestXML.cell(cell)])
            + TestXML.paragraph("0000A251", TestXML.run("後") + "<w:bookmarkEnd w:id=\"12\"/>")
            + TestXML.bodySection
        let out = try apply(body, FormPlan(removals: ["0000R250"]))
        let index = try XMLTagIndex(out)
        let tc = index.elements(named: "w:tc").first!
        XCTAssertEqual(index.tags[index.children(of: tc).last!].name, "w:p", "the cell still ends with a paragraph")
        let start = try XCTUnwrap(index.elements(named: "w:bookmarkStart").first)
        XCTAssertEqual(index.attribute("w14:paraId", of: index.tags[start].parent!), "0000A250")
    }

    func testRemovingTheLastParagraphOfACellAfterASelfClosingParagraph() throws {
        let cell = "<w:p w14:paraId=\"0000A260\"/>"
            + TestXML.paragraph("0000R260", "<w:permStart w:id=\"13\"/>" + TestXML.run("刪"))
        let body = TestXML.table([TestXML.cell(cell)])
            + TestXML.paragraph("0000A261", "<w:permEnd w:id=\"13\"/>")
            + TestXML.bodySection
        let out = try apply(body, FormPlan(removals: ["0000R260"]))
        XCTAssertTrue(out.contains("<w:p w14:paraId=\"0000A260\"><w:permStart w:id=\"13\"/></w:p>"), out)
    }

    /// R1 #4: a moved marker keeps the namespace bindings it was using.
    func testKeptMarkerCarriesNamespacesDeclaredOnTheRemovedParagraph() throws {
        let removed = "<w:p w14:paraId=\"0000R270\" xmlns:foo=\"urn:example:foo\">"
            + "<w:bookmarkStart w:id=\"14\" w:name=\"n\" foo:tag=\"1\"/>" + TestXML.run("刪") + "</w:p>"
        let body = TestXML.paragraph("0000A270", TestXML.run("前")) + removed
            + TestXML.paragraph("0000A271", TestXML.run("後") + "<w:bookmarkEnd w:id=\"14\"/>")
            + TestXML.bodySection
        let out = try apply(body, FormPlan(removals: ["0000R270"]))
        XCTAssertTrue(out.contains("<w:bookmarkStart w:id=\"14\" w:name=\"n\" foo:tag=\"1\" xmlns:foo=\"urn:example:foo\"/>"), out)
        let parser = XMLParser(data: Data(out.utf8))
        parser.shouldProcessNamespaces = true
        XCTAssertTrue(parser.parse(), "namespace-aware parse: \(String(describing: parser.parserError))")
    }

    /// R1 #6: every kind in the closed list of paired markers.
    func testEveryPairedMarkerKindIsKeptWhenItsPartnerStays() throws {
        for (start, end) in FormRanges.pairedMarkers.filter({ $0.value.isStart }).map({ ($0.key, $0.key.replacingOccurrences(of: "Start", with: "End")) }) {
            XCTAssertNotNil(FormRanges.pairedMarkers[end], end)
            let body = TestXML.paragraph("0000A280", TestXML.run("前"))
                + TestXML.paragraph("0000R280", "<\(start) w:id=\"21\"/>" + TestXML.run("刪"))
                + TestXML.paragraph("0000A281", TestXML.run("後") + "<\(end) w:id=\"21\"/>")
                + TestXML.bodySection
            let out = try apply(body, FormPlan(removals: ["0000R280"]))
            XCTAssertTrue(out.contains("<\(start) w:id=\"21\"/>"), start)
            XCTAssertTrue(out.contains("<\(end) w:id=\"21\"/>"), end)
        }
        XCTAssertEqual(FormRanges.pairedMarkers.count, 18)
    }

    /// R1 #7: nothing to clean means nothing to report.
    func testNoSkipIsReportedWhenTheCellHasNothingToClean() throws {
        let control = "<w:sdt><w:sdtPr><w:dropDownList/></w:sdtPr><w:sdtContent>" + TestXML.run("選項一") + "</w:sdtContent></w:sdt>"
        let out = try result(TestXML.table([TestXML.cell(TestXML.paragraph("0000F290", control))]),
                             FormPlan(fields: ["0000F290"], fieldSize: try FieldSize.parse(points: "12")))
        XCTAssertEqual(out.skippedCleanups, [])
    }

    // MARK: verify round 2 (#253)

    /// R2 #1: the last two paragraphs of a cell, removed in either order.
    func testRemovingTheLastTwoParagraphsOfACellKeepsTheirMarkersInEitherOrder() throws {
        let cell = TestXML.paragraph("0000A300", TestXML.run("前"))
            + TestXML.paragraph("0000R300", "<w:bookmarkStart w:id=\"31\" w:name=\"p\"/>" + TestXML.run("一"))
            + TestXML.paragraph("0000R301", "<w:permStart w:id=\"32\"/>" + TestXML.run("二"))
        let body = TestXML.table([TestXML.cell(cell)])
            + TestXML.paragraph("0000A301", TestXML.run("後") + "<w:bookmarkEnd w:id=\"31\"/><w:permEnd w:id=\"32\"/>")
            + TestXML.bodySection
        for order in [["0000R300", "0000R301"], ["0000R301", "0000R300"]] {
            let out = try apply(body, FormPlan(removals: order))
            let index = try XMLTagIndex(out)
            let tc = index.elements(named: "w:tc").first!
            XCTAssertEqual(index.tags[index.children(of: tc).last!].name, "w:p", "\(order)")
            let kept = index.elementString(index.children(of: tc).last!)
            XCTAssertTrue(kept.contains("<w:bookmarkStart w:id=\"31\" w:name=\"p\"/><w:permStart w:id=\"32\"/></w:p>"), "\(order): \(kept)")
            XCTAssertTrue(out.contains("<w:bookmarkEnd w:id=\"31\"/>") && out.contains("<w:permEnd w:id=\"32\"/>"))
        }
    }

    func testRemovedParagraphsWithASurvivingBlockAfterThemKeepMarkersInPlace() throws {
        let cell = TestXML.paragraph("0000A310", TestXML.run("前"))
            + TestXML.paragraph("0000R310", "<w:bookmarkStart w:id=\"34\" w:name=\"q\"/>" + TestXML.run("一"))
            + TestXML.paragraph("0000R311", TestXML.run("二"))
            + TestXML.paragraph("0000A311", TestXML.run("留"))
        let body = TestXML.table([TestXML.cell(cell)])
            + TestXML.paragraph("0000A312", "<w:bookmarkEnd w:id=\"34\"/>") + TestXML.bodySection
        let out = try apply(body, FormPlan(removals: ["0000R311", "0000R310"]))
        let start = try XCTUnwrap(out.range(of: "<w:bookmarkStart w:id=\"34\" w:name=\"q\"/>"))
        XCTAssertLessThan(try XCTUnwrap(out.range(of: "0000A310")).lowerBound, start.lowerBound)
        XCTAssertLessThan(start.lowerBound, try XCTUnwrap(out.range(of: "0000A311")).lowerBound)
    }

    /// R2 #2: the moved marker keeps the binding it had, not the destination's.
    func testMovedMarkerKeepsItsNamespaceWhenTheDestinationRebindsThePrefix() throws {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<w:document \(TestXML.namespaces) xmlns:foo=\"urn:a\"><w:body>"
            + TestXML.table([TestXML.cell(
                "<w:p w14:paraId=\"0000A320\" xmlns:foo=\"urn:b\">" + TestXML.run("前") + "</w:p>"
                + TestXML.paragraph("0000R320", "<w:bookmarkStart w:id=\"35\" w:name=\"r\" foo:tag=\"1\"/>" + TestXML.run("刪")))])
            + TestXML.paragraph("0000A321", "<w:bookmarkEnd w:id=\"35\"/>") + TestXML.bodySection
            + "</w:body></w:document>"
        let out = TestXML.string(try FormPlan(removals: ["0000R320"]).apply(toDocumentXML: Array(xml.utf8)).documentXML)
        XCTAssertTrue(out.contains("<w:bookmarkStart w:id=\"35\" w:name=\"r\" foo:tag=\"1\" xmlns:foo=\"urn:a\"/>"), out)
    }

    /// R2 #3: text that only looks like a declaration inside a value is not one.
    func testAnAttributeValueMentioningXmlnsIsNotADeclaration() throws {
        let removed = "<w:p w14:paraId=\"0000R330\" w:rsidR='xmlns:foo=\"urn:evil\"'>"
            + "<w:bookmarkStart w:id=\"36\" w:name=\"s\"/>" + TestXML.run("刪") + "</w:p>"
        let body = TestXML.paragraph("0000A330", TestXML.run("前")) + removed
            + TestXML.paragraph("0000A331", "<w:bookmarkEnd w:id=\"36\"/>") + TestXML.bodySection
        let out = try apply(body, FormPlan(removals: ["0000R330"]))
        XCTAssertTrue(out.contains("<w:bookmarkStart w:id=\"36\" w:name=\"s\"/>"), out)
        XCTAssertFalse(out.contains("urn:evil"))
    }

    /// R2 #8: the batch removal entry point checks fields itself.
    func testRemoveAllRefusesASplitFieldWithoutThePlan() throws {
        let body = TestXML.paragraph("0000A340", TestXML.run("前"))
            + TestXML.paragraph("0000R340", begin + separate + TestXML.run("目錄"))
            + TestXML.paragraph("0000A341", TestXML.run("項目") + end)
            + TestXML.bodySection
        var editor = try XMLEditor(TestXML.document(body))
        XCTAssertThrowsError(try FormOperations.deleteAll(["0000R340"], truncateFrom: nil, editor: &editor)) {
            XCTAssertEqual($0 as? FormError, .splitsField("0000R340"))
        }
    }

    func testRemovingEveryParagraphOfACellIsRefusedAsAWhole() {
        let cell = TestXML.paragraph("0000R350", TestXML.run("一")) + TestXML.paragraph("0000R351", TestXML.run("二"))
        let body = TestXML.table([TestXML.cell(cell)]) + TestXML.paragraph(nil) + TestXML.bodySection
        XCTAssertThrowsError(try apply(body, FormPlan(removals: ["0000R350", "0000R351"]))) {
            XCTAssertEqual($0 as? FormError, .removalsLeaveNoParagraph(["0000R350", "0000R351"]))
        }
    }

    /// Removing P2 or P3 alone leaves a paragraph last, but removing both
    /// leaves the nested table last. Only the paragraphs after the last block
    /// that stays exposed it, so only they are named; P0, removed before the
    /// table, is not.
    func testRemovalsThatTogetherEndACellWithATableNameTheParagraphsAfterIt() {
        let nested = TestXML.table([TestXML.cell(TestXML.paragraph("0000N360", TestXML.run("內層")))])
        let cell = TestXML.paragraph("0000R360", TestXML.run("零")) + TestXML.paragraph("0000R361", TestXML.run("一"))
            + nested + TestXML.paragraph("0000R362", TestXML.run("二")) + TestXML.paragraph("0000R363", TestXML.run("三"))
        let body = TestXML.table([TestXML.cell(cell)]) + TestXML.paragraph(nil) + TestXML.bodySection
        XCTAssertThrowsError(try apply(body, FormPlan(removals: ["0000R363", "0000R360", "0000R362"]))) {
            XCTAssertEqual($0 as? FormError, .removalsEndWithoutParagraph(["0000R362", "0000R363"]))
        }
    }

    func testBatchCellRefusalsNameEveryParagraph() {
        let empty = FormError.removalsLeaveNoParagraph(["0000R350", "0000R351"]).description
        XCTAssertTrue(empty.contains("0000R350") && empty.contains("0000R351"))
        let table = FormError.removalsEndWithoutParagraph(["0000R362", "0000R363"]).description
        XCTAssertTrue(table.contains("0000R362") && table.contains("0000R363"))
    }

    // MARK: verify round 3

    private func document(root extra: String, _ body: String) -> [UInt8] {
        Array(("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<w:document \(TestXML.namespaces) \(extra)><w:body>" + body + "</w:body></w:document>").utf8)
    }

    // MARK: verify round 4 — Markup Compatibility context is never moved

    private let mcURI = "http://schemas.openxmlformats.org/markup-compatibility/2006"

    private func refusal(_ xml: [UInt8], _ plan: FormPlan) -> FormError? {
        do { _ = try plan.apply(toDocumentXML: xml); return nil } catch { return error as? FormError }
    }

    /// R4 #1: a kept marker that carries a Markup Compatibility attribute is
    /// not moved: its value names prefixes whose meaning depends on where the
    /// marker sits, so the removal is refused instead.
    func testKeptMarkerCarryingAnIgnorableAttributeIsRefused() {
        let xml = document(root: "xmlns:mc=\"\(mcURI)\"",
            "<w:p w14:paraId=\"0000R370\" xmlns:foo=\"urn:x\">"
            + "<w:bookmarkStart w:id=\"41\" w:name=\"i\" mc:Ignorable=\"f&#111;o w14\"/>" + TestXML.run("刪") + "</w:p>"
            + TestXML.paragraph("0000A370", TestXML.run("後") + "<w:bookmarkEnd w:id=\"41\"/>") + TestXML.bodySection)
        XCTAssertEqual(refusal(xml, FormPlan(removals: ["0000R370"])), .markerUnderCompatibilityRules("0000R370"))
    }

    /// R4 #2: the rule on a removed ancestor would stop applying to the marker.
    func testKeptMarkerUnderARemovedParagraphWithCompatibilityRulesIsRefused() {
        let xml = document(root: "xmlns:mc=\"\(mcURI)\"",
            "<w:p w14:paraId=\"0000R371\" xmlns:foo=\"urn:x\" mc:Ignorable=\"foo\">"
            + "<w:bookmarkStart w:id=\"44\" w:name=\"j\" foo:tag=\"1\"/>" + TestXML.run("刪") + "</w:p>"
            + TestXML.paragraph("0000A371", TestXML.run("後") + "<w:bookmarkEnd w:id=\"44\"/>") + TestXML.bodySection)
        XCTAssertEqual(refusal(xml, FormPlan(removals: ["0000R371"])), .markerUnderCompatibilityRules("0000R371"))
    }

    /// R4 #2: the rule on the destination paragraph would start applying.
    func testKeptMarkerMovingIntoAParagraphWithCompatibilityRulesIsRefused() {
        let cell = "<w:p w14:paraId=\"0000A372\" mc:Ignorable=\"w14\">" + TestXML.run("前") + "</w:p>"
            + TestXML.paragraph("0000R372", "<w:bookmarkStart w:id=\"45\" w:name=\"k\"/>" + TestXML.run("刪"))
        let xml = document(root: "xmlns:mc=\"\(mcURI)\"", TestXML.table([TestXML.cell(cell)])
            + TestXML.paragraph("0000A373", "<w:bookmarkEnd w:id=\"45\"/>") + TestXML.bodySection)
        XCTAssertEqual(refusal(xml, FormPlan(removals: ["0000R372"])), .markerUnderCompatibilityRules("0000R372"))
    }

    /// R4 #3: an MC attribute is known by the namespace its prefix resolves
    /// to, with character references in the declared URI decoded, not by the
    /// spelling `mc`.
    func testCompatibilityAttributesAreKnownByNamespace() {
        for root in ["xmlns:compat=\"\(mcURI)\"", "xmlns:compat=\"http&#58;//schemas.openxmlformats.org/markup-compatibility/2006\""] {
            let xml = document(root: root,
                TestXML.paragraph("0000R374", "<w:bookmarkStart w:id=\"46\" w:name=\"l\" compat:ProcessContent=\"w14:sdt\"/>"
                                  + TestXML.run("刪"))
                + TestXML.paragraph("0000A374", "<w:bookmarkEnd w:id=\"46\"/>") + TestXML.bodySection)
            XCTAssertEqual(refusal(xml, FormPlan(removals: ["0000R374"])), .markerUnderCompatibilityRules("0000R374"), root)
        }
    }

    /// An attribute that is merely named Ignorable in another namespace is
    /// not a compatibility rule, and a removed paragraph with MC rules but no
    /// marker that stays is removed as usual.
    func testCompatibilityRefusalIsLimitedToMovedMarkers() throws {
        let plain = document(root: "xmlns:foo=\"urn:x\"",
            TestXML.paragraph("0000R375", "<w:bookmarkStart w:id=\"47\" w:name=\"m\" foo:Ignorable=\"w14\"/>" + TestXML.run("刪"))
            + TestXML.paragraph("0000A375", "<w:bookmarkEnd w:id=\"47\"/>") + TestXML.bodySection)
        XCTAssertTrue(TestXML.string(try FormPlan(removals: ["0000R375"]).apply(toDocumentXML: plain).documentXML)
            .contains("<w:bookmarkStart w:id=\"47\" w:name=\"m\" foo:Ignorable=\"w14\"/>"))
        let unmarked = document(root: "xmlns:mc=\"\(mcURI)\"",
            "<w:p w14:paraId=\"0000R376\" mc:Ignorable=\"w14\">" + TestXML.run("刪") + "</w:p>"
            + TestXML.paragraph("0000A376", TestXML.run("留")) + TestXML.bodySection)
        XCTAssertFalse(TestXML.string(try FormPlan(removals: ["0000R376"]).apply(toDocumentXML: unmarked).documentXML)
            .contains("0000R376"))
    }

    /// R4 #2 for the cut: the marker would leave the cut paragraph's rules.
    func testTruncatedMarkerUnderCompatibilityRulesIsRefused() {
        let xml = document(root: "xmlns:mc=\"\(mcURI)\"",
            TestXML.paragraph("0000A377", "<w:bookmarkStart w:id=\"48\" w:name=\"n\"/>" + TestXML.run("留"))
            + "<w:p w14:paraId=\"0000T377\" mc:Ignorable=\"w14\">" + TestXML.run("切") + "<w:bookmarkEnd w:id=\"48\"/></w:p>"
            + TestXML.bodySection)
        XCTAssertEqual(refusal(xml, FormPlan(truncateFrom: "0000T377")), .markerUnderCompatibilityRules("0000T377"))
    }

    /// R4 #4: removing everything before the cut is refused before any edit,
    /// naming the cut and saying why.
    func testRemovingEverythingBeforeTheCutIsRefusedUpFront() {
        let body = TestXML.paragraph("0000R378", TestXML.run("唯一")) + TestXML.paragraph("0000T378", TestXML.run("切"))
            + TestXML.bodySection
        XCTAssertEqual(refusal(TestXML.document(body), FormPlan(removals: ["0000R378"], truncateFrom: "0000T378")),
                       .removalsLeaveNothingBeforeCut("0000T378"))
    }

    /// R4 #5, R5 #4: a repeated id is one paragraph, named once, also for a
    /// caller that reaches the check without the plan's own deduplication.
    func testRepeatedRemovalIdIsNamedOnce() throws {
        let cell = TestXML.paragraph("0000R379", TestXML.run("一")) + TestXML.paragraph("0000R380", TestXML.run("二"))
        let index = try XMLTagIndex(TestXML.document(TestXML.table([TestXML.cell(cell)]) + TestXML.paragraph(nil)
                                                     + TestXML.bodySection))
        XCTAssertThrowsError(try FormOperations.checkDeletions(["0000R379", "0000R379", "0000R380"], truncateFrom: nil, in: index)) {
            XCTAssertEqual($0 as? FormError, .removalsLeaveNoParagraph(["0000R379", "0000R380"]))
        }
    }

    /// R5 #1: Word 2010 and later wrap a text box in mc:AlternateContent with
    /// one copy under mc:Choice and one under mc:Fallback. A marker inside
    /// either would leave that branch, so the removal is refused.
    func testKeptMarkerInsideAlternateContentIsRefused() {
        let story = { (id: String) in "<w:txbxContent><w:p><w:bookmarkStart w:id=\"50\" w:name=\"t\"/>"
            + TestXML.run(id) + "</w:p></w:txbxContent>" }
        let box = "<w:r><mc:AlternateContent><mc:Choice Requires=\"w14\"><w:drawing><wp:inline>" + story("新")
            + "</wp:inline></w:drawing></mc:Choice><mc:Fallback><w:pict>" + story("舊")
            + "</w:pict></mc:Fallback></mc:AlternateContent></w:r>"
        let xml = document(root: "xmlns:mc=\"\(mcURI)\"",
            TestXML.paragraph("0000R381", box) + TestXML.paragraph("0000A381", "<w:bookmarkEnd w:id=\"50\"/>")
            + TestXML.bodySection)
        XCTAssertEqual(refusal(xml, FormPlan(removals: ["0000R381"])), .markerUnderCompatibilityRules("0000R381"))
    }

    /// R5 #2: a crafted part whose root is a named paragraph used to trap on a
    /// force unwrap. It must end either in a FormError or in a result that has
    /// passed the plan's own well-formedness check — never in a crash.
    func testRemovingARootParagraphDoesNotTrap() throws {
        let xml = Array("<w:p xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:w14=\"http://schemas.microsoft.com/office/word/2010/wordml\" w14:paraId=\"0000R382\"><w:bookmarkStart w:id=\"51\" w:name=\"r\"/></w:p>".utf8)
        do {
            let result = try FormPlan(removals: ["0000R382"]).apply(toDocumentXML: xml)
            XCTAssertNoThrow(try XMLTagIndex(result.documentXML))
        } catch {
            XCTAssertNotNil(error as? FormError, "\(error)")
        }
    }

    /// R3 #3: the truncation destination is the body, so a prefix the cut
    /// paragraph rebinds is declared on the moved marker.
    func testTruncatedMarkerKeepsTheNamespaceItsPrefixHadInTheCut() throws {
        let xml = document(root: "xmlns:foo=\"urn:a\"",
            TestXML.paragraph("0000A380", "<w:bookmarkStart w:id=\"42\" w:name=\"t\"/>" + TestXML.run("留"))
            + "<w:p w14:paraId=\"0000T380\" xmlns:foo=\"urn:b\">" + TestXML.run("切")
            + "<w:bookmarkEnd w:id=\"42\" foo:tag=\"1\"/></w:p>" + TestXML.bodySection)
        let out = TestXML.string(try FormPlan(truncateFrom: "0000T380").apply(toDocumentXML: xml).documentXML)
        XCTAssertTrue(out.contains("<w:bookmarkEnd w:id=\"42\" foo:tag=\"1\" xmlns:foo=\"urn:b\"/><w:sectPr"), out)
    }

    /// R3 #6: a text box follows the same rule as a cell.
    func testRemovingTheLastParagraphOfATextBoxKeepsItsMarkerInTheBox() throws {
        let box = "<w:r><w:drawing><wp:inline><w:txbxContent>"
            + TestXML.paragraph("0000A390", TestXML.run("前"))
            + TestXML.paragraph("0000R390", "<w:bookmarkStart w:id=\"43\" w:name=\"b\"/>" + TestXML.run("刪"))
            + "</w:txbxContent></wp:inline></w:drawing></w:r>"
        let body = TestXML.paragraph("0000A391", box) + TestXML.paragraph("0000A392", "<w:bookmarkEnd w:id=\"43\"/>")
            + TestXML.bodySection
        let out = try apply(body, FormPlan(removals: ["0000R390"]))
        XCTAssertTrue(out.contains(TestXML.run("前") + "<w:bookmarkStart w:id=\"43\" w:name=\"b\"/></w:p></w:txbxContent>"), out)
    }

    /// R3 #2: removal and truncation share one entry point that checks the
    /// whole deletion itself, so no caller can cut a field in two.
    func testDeleteAllRefusesATruncationThatSplitsAFieldWithoutThePlan() throws {
        let body = TestXML.paragraph("0000A400", begin + separate + TestXML.run("目錄"))
            + TestXML.paragraph("0000T400", TestXML.run("項目") + end) + TestXML.bodySection
        var editor = try XMLEditor(TestXML.document(body))
        XCTAssertThrowsError(try FormOperations.deleteAll([], truncateFrom: "0000T400", editor: &editor)) {
            XCTAssertEqual($0 as? FormError, .splitsField("0000T400"))
        }
    }

    /// R3 #4: with nothing to delete the step leaves the part as it is.
    func testDeleteAllWithNothingToDeleteLeavesThePartUnchanged() throws {
        let xml = TestXML.document(TestXML.paragraph("0000A410", TestXML.run("一")) + TestXML.bodySection)
        var editor = try XMLEditor(xml)
        try FormOperations.deleteAll([], truncateFrom: nil, editor: &editor)
        XCTAssertEqual(editor.bytes, xml)
    }

    func testRefusalMessagesSayWhatToDo() {
        XCTAssertTrue(FormError.splitsField("0000R060").description.contains("0000R060"))
        XCTAssertTrue(FormError.splitsField("0000R060").description.contains("w:fldChar"))
        XCTAssertTrue(FormError.splitsComment("0000R090").description.contains("w:commentReference"))
    }
}
