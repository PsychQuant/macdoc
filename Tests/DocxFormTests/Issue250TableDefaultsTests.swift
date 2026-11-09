// Issue250TableDefaultsTests.swift — `--table-defaults <paraId>=col:…/row:…`
// (macdoc#250 requirement 1): the caller names a table and its fill columns
// or rows on the table's grid; every cell that lies wholly inside the
// selection is tidied the way `--field` tidies one paragraph, label cells
// are left alone, and cells only partly inside are left alone and reported.

import XCTest
@testable import DocxForm

final class Issue250TableDefaultsTests: XCTestCase {

    // MARK: builders

    /// A paragraph with one run; `size` sets the run's w:sz (half-points).
    private func p(_ id: String?, _ text: String = "", size: Int? = nil) -> String {
        guard !text.isEmpty else { return TestXML.paragraph(id) }
        let rPr = size.map { "<w:rPr><w:sz w:val=\"\($0)\"/></w:rPr>" } ?? ""
        return TestXML.paragraph(id, TestXML.run(text, rPr: rPr))
    }

    /// A cell; `span` writes w:gridSpan, `vMerge` writes w:vMerge ("" for
    /// the bare continuation form), `extra` is appended to w:tcPr as is.
    private func tc(_ content: String, span: Int? = nil, vMerge: String? = nil, extra: String = "") -> String {
        var tcPr = "<w:tcW w:w=\"2000\" w:type=\"dxa\"/>"
        if let span { tcPr += "<w:gridSpan w:val=\"\(span)\"/>" }
        if let vMerge { tcPr += vMerge.isEmpty ? "<w:vMerge/>" : "<w:vMerge w:val=\"\(vMerge)\"/>" }
        return "<w:tc><w:tcPr>\(tcPr)\(extra)</w:tcPr>\(content)</w:tc>"
    }

    private func tr(_ cells: String..., trPr: String = "") -> String {
        "<w:tr>\(trPr)\(cells.joined())</w:tr>"
    }

    private func gridBefore(_ n: String) -> String { "<w:trPr><w:gridBefore w:val=\"\(n)\"/></w:trPr>" }

    private func tbl(_ rows: String...) -> String {
        "<w:tbl><w:tblPr/><w:tblGrid/>\(rows.joined())</w:tbl>"
    }

    private func grid(_ table: String) throws -> TableGrid {
        let index = try XMLTagIndex(TestXML.document(table + TestXML.bodySection))
        return try TableGrid(table: index.elements(named: "w:tbl")[0], in: index)
    }

    private func apply(_ body: String, _ plan: FormPlan) throws -> FormResult {
        try plan.apply(toDocumentXML: TestXML.document(body + TestXML.bodySection))
    }

    private func refusal(_ body: String, _ plan: FormPlan) -> FormError? {
        do {
            _ = try apply(body, plan)
            return nil
        } catch {
            return error as? FormError
        }
    }

    private func spec(_ raw: String) throws -> TableDefaults { try TableDefaults.parse(raw) }

    private func position(_ id: String, in classified: [ClassifiedParagraph]) -> CellPosition? {
        classified.first { $0.paraId == id }?.cell
    }

    /// The `w:tc` around the paragraph `id`, as a string.
    private func cellXML(_ id: String, in bytes: [UInt8]) throws -> String {
        let index = try XMLTagIndex(bytes)
        guard case .found(let para) = FormLocator.paragraph(withId: id, in: index),
              let cell = index.ancestor(of: para, named: "w:tc") else { return "" }
        return index.elementString(cell)
    }

    /// The Diagnosis example: a title across four grid columns, a row of
    /// label / fill / label / fill, and an address fill across columns 2–4.
    private var exampleTable: String {
        tbl(
            tr(tc(p("0000T001", "申請表"), span: 4)),
            tr(tc(p("0000L001", "姓名", size: 24)), tc(p("0000F001", "王小明", size: 20)),
               tc(p("0000L002", "電話", size: 24)), tc(p("0000F002", "0912", size: 20))),
            tr(tc(p("0000L003", "地址", size: 24)), tc(p("0000F003", "臺北市", size: 28), span: 3)))
    }

    private let exampleIds = ["0000T001", "0000L001", "0000F001", "0000L002", "0000F002", "0000L003", "0000F003"]

    // MARK: syntax

    func testColumnListWithRangesAndAnOpenEndParses() throws {
        let parsed = try spec("0000A001=col:2,4-5,7-")
        XCTAssertEqual(parsed.anchor, "0000A001")
        XCTAssertEqual(parsed.columns, try GridSelection(items: [.single(2), .range(4, 5), .from(7)]))
        XCTAssertNil(parsed.rows)
    }

    func testColumnsAndRowsTogetherParseInEitherOrder() throws {
        let parsed = try spec("0000A001=row:3-/col:2")
        XCTAssertEqual(parsed.columns, try GridSelection(items: [.single(2)]))
        XCTAssertEqual(parsed.rows, try GridSelection(items: [.from(3)]))
    }

    func testMalformedSelectionsAreRefusedWithTheValueAsWritten() {
        let malformed = [
            "0000A001", "=col:2", "0000A001=", "0000A001=cols:2", "0000A001=col:", "0000A001=col:0",
            "0000A001=col:3-2", "0000A001=col:2,", "0000A001=col:x", "0000A001=col: 2", "0000A001=col:2/col:3",
            "0000A001=col:2/", "0000A001=col:2/row:1/col:3", "0000A001=col:99999999999999999999", "0000A001=col:-2",
        ]
        for raw in malformed {
            XCTAssertThrowsError(try spec(raw), raw) { error in
                guard case FormError.invalidTableDefaults(let value, _) = error else {
                    return XCTFail("\(raw): unexpected \(error)")
                }
                XCTAssertEqual(value, raw)
            }
        }
    }

    /// Verify R1 (codex): the public initialiser enforces what the parser
    /// enforces, so a library caller cannot build a selection that crashes.
    func testASelectionBuiltDirectlyIsCheckedAtConstruction() throws {
        let invalid: [[GridSelection.Item]] = [[], [.single(0)], [.single(-1)], [.range(3, 2)], [.range(0, 2)], [.from(0)]]
        for items in invalid {
            XCTAssertThrowsError(try GridSelection(items: items), "\(items)") { error in
                guard case FormError.invalidGridSelection = error else { return XCTFail("\(items): \(error)") }
            }
        }
        XCTAssertNoThrow(try GridSelection(items: [.single(1), .range(2, 2), .from(3)]))
    }

    // MARK: grid

    func testPlainCellsAreNumberedFromOne() throws {
        let g = try grid(tbl(tr(tc(p("0000A001")), tc(p("0000A002"))), tr(tc(p("0000A003")), tc(p("0000A004")))))
        XCTAssertEqual(g.cells.map(\.label), ["r1c1", "r1c2", "r2c1", "r2c2"])
        XCTAssertEqual(g.columnCount, 2)
        XCTAssertEqual(g.rowCount, 2)
    }

    func testGridSpanAndGridBeforePlaceCellsOnTheGrid() throws {
        let g = try grid(tbl(
            tr(tc(p("0000A001"), span: 3)),
            tr(tc(p("0000A002")), tc(p("0000A003"), span: 2)),
            tr(tc(p("0000A004")), trPr: gridBefore("2"))))
        XCTAssertEqual(g.cells.map(\.label), ["r1c1-3", "r2c1", "r2c2-3", "r3c3"])
        XCTAssertEqual(g.columnCount, 3)
    }

    func testVerticalMergeJoinsContinuationCellsIntoTheCellAbove() throws {
        let g = try grid(tbl(
            tr(tc(p("0000A001")), tc(p("0000A002"), vMerge: "restart")),
            tr(tc(p("0000A003")), tc(p(nil), vMerge: "")),
            tr(tc(p("0000A004")), tc(p(nil), vMerge: "continue"))))
        XCTAssertEqual(g.cells.map(\.label), ["r1c1", "r1-3c2", "r2c1", "r3c1"])
        XCTAssertEqual(g.rowCount, 3)
    }

    func testRowsAndCellsInsideWrappersAreCounted() throws {
        let wrappedRow = "<w:sdt><w:sdtPr/><w:sdtContent>"
            + tr(tc(p("0000A003")), "<w:customXml w:element=\"x\">" + tc(p("0000A004")) + "</w:customXml>")
            + "</w:sdtContent></w:sdt>"
        let g = try grid(tbl(tr(tc(p("0000A001")), tc(p("0000A002"))), wrappedRow))
        XCTAssertEqual(g.cells.map(\.label), ["r1c1", "r1c2", "r2c1", "r2c2"])
    }

    func testGridsThatCannotBeReadAreRefused() {
        let unreadable: [(String, String)] = [
            ("gridSpan 0", tbl(tr(tc(p("0000A001"), span: 0)))),
            ("gridSpan not a number", tbl(tr(tc(p("0000A001"), extra: "<w:gridSpan w:val=\"x\"/>")))),
            ("gridSpan without a value", tbl(tr(tc(p("0000A001"), extra: "<w:gridSpan/>")))),
            ("negative gridBefore", tbl(tr(tc(p("0000A001")), trPr: gridBefore("-1")))),
            ("legacy hMerge", tbl(tr(tc(p("0000A001"), extra: "<w:hMerge w:val=\"restart\"/>"), tc(p("0000A002"))))),
            ("continuation in the first row", tbl(tr(tc(p("0000A001"), vMerge: "")))),
            ("continuation under a plain cell", tbl(tr(tc(p("0000A001"))), tr(tc(p("0000A002"), vMerge: "continue")))),
            ("continuation under a cell of another width",
             tbl(tr(tc(p("0000A001"), span: 2, vMerge: "restart")), tr(tc(p("0000A002"), vMerge: ""), tc(p("0000A003"))))),
            ("unknown vMerge value", tbl(tr(tc(p("0000A001"), vMerge: "maybe")))),
            ("gridSpan too large for Int", tbl(tr(tc(p("0000A001"), extra: "<w:gridSpan w:val=\"99999999999999999999\"/>")))),
            ("gridBefore at Int.max", tbl(tr(tc(p("0000A001")), trPr: gridBefore("\(Int.max)")))),
            ("columns past Int.max", tbl(tr(tc(p("0000A001")), tc(p("0000A002"), extra: "<w:gridSpan w:val=\"\(Int.max)\"/>")))),
        ]
        for (name, table) in unreadable {
            XCTAssertThrowsError(try grid(table), name) { error in
                XCTAssertTrue(error is TableGrid.Unreadable, "\(name): \(error)")
            }
        }
    }

    // MARK: applying

    func testNamedColumnsTidyTheFillCellsAndLeaveLabelsAlone() throws {
        let before = TestXML.document(exampleTable + TestXML.bodySection)
        let result = try apply(exampleTable, FormPlan(tableDefaults: [try spec("0000L001=col:2,4")]))
        let out = result.documentXML
        for id in ["0000F001", "0000F002"] {
            let paragraph = try TestXML.paragraphXML(id, in: out)
            XCTAssertTrue(paragraph.contains("<w:jc w:val=\"left\"/>"), id)
            XCTAssertTrue(paragraph.contains("<w:sz w:val=\"20\"/><w:szCs w:val=\"20\"/>"), id)
            XCTAssertTrue(try cellXML(id, in: out).contains("<w:vAlign w:val=\"center\"/>"), id)
        }
        // Labels, the title and the address (only partly in columns 2 and 4) are untouched.
        for id in ["0000T001", "0000L001", "0000L002", "0000L003", "0000F003"] {
            XCTAssertEqual(try cellXML(id, in: out), try cellXML(id, in: before), id)
        }
        XCTAssertEqual(result.fieldSize, FieldSize(halfPoints: 20))
        XCTAssertTrue(result.fieldSizeWasDerived)
        XCTAssertEqual(result.tableDefaultsReports,
                       [TableDefaultsReport(anchor: "0000L001", fillCells: 2, partialCells: ["r1c1-4", "r3c2-4"])])
    }

    func testTwoSelectionsOnOneTableTakeTheUnionOfTheirFillCells() throws {
        let result = try apply(exampleTable, FormPlan(tableDefaults: [
            try spec("0000L001=col:2,4"), try spec("0000F003=col:2-4/row:3"),
        ]))
        let address = try TestXML.paragraphXML("0000F003", in: result.documentXML)
        XCTAssertTrue(address.contains("<w:jc w:val=\"left\"/>"))
        XCTAssertTrue(address.contains("<w:sz w:val=\"20\"/>"), "one size for every field: the mode of 20, 20, 28")
        XCTAssertEqual(result.tableDefaultsReports, [
            TableDefaultsReport(anchor: "0000L001", fillCells: 2, partialCells: ["r1c1-4"]),
            TableDefaultsReport(anchor: "0000F003", fillCells: 1, partialCells: []),
        ])
    }

    func testAdjacentNumbersCoverACellSpanningThem() throws {
        // 2,3,4 is one stretch of columns, so the address across 2–4 is inside it.
        let result = try apply(exampleTable, FormPlan(tableDefaults: [try spec("0000L003=col:2,3,4/row:3")]))
        XCTAssertTrue(try TestXML.paragraphXML("0000F003", in: result.documentXML).contains("<w:jc w:val=\"left\"/>"))
        XCTAssertEqual(result.tableDefaultsReports, [TableDefaultsReport(anchor: "0000L003", fillCells: 1, partialCells: [])])
    }

    func testAnEmptyAnchorInAFillCellIsCleanedUpLikeAnyOtherEmptyParagraph() throws {
        // The anchor only says which table is meant; it is not kept as if named by --field.
        let table = tbl(tr(tc(p("0000L001", "姓名")), tc(p("0000F001", "王小明", size: 20) + p("0000E001"))))
        let out = try apply(table, FormPlan(tableDefaults: [try spec("0000E001=col:2")])).documentXML
        XCTAssertFalse(TestXML.string(out).contains("0000E001"))
        XCTAssertTrue(try TestXML.paragraphXML("0000F001", in: out).contains("<w:jc w:val=\"left\"/>"))
    }

    func testColumnsAndRowsTogetherSelectTheirIntersection() throws {
        let matrix = tbl(
            tr(tc(p("0000H000", "項目")), tc(p("0000H001", "上學期")), tc(p("0000H002", "下學期"))),
            tr(tc(p("0000R001", "國文")), tc(p("0000M011", "90", size: 20)), tc(p("0000M012", "88", size: 20))),
            tr(tc(p("0000R002", "數學")), tc(p("0000M021", "75", size: 20)), tc(p("0000M022", "80", size: 20))))
        let before = TestXML.document(matrix + TestXML.bodySection)
        let result = try apply(matrix, FormPlan(tableDefaults: [try spec("0000H000=col:2-/row:2-")]))
        for id in ["0000M011", "0000M012", "0000M021", "0000M022"] {
            XCTAssertTrue(try TestXML.paragraphXML(id, in: result.documentXML).contains("<w:jc w:val=\"left\"/>"), id)
        }
        for id in ["0000H000", "0000H001", "0000H002", "0000R001", "0000R002"] {
            XCTAssertEqual(try cellXML(id, in: result.documentXML), try cellXML(id, in: before), id)
        }
        XCTAssertEqual(result.tableDefaultsReports, [TableDefaultsReport(anchor: "0000H000", fillCells: 4, partialCells: [])])
    }

    func testAnEmptyFillCellKeepsItsFirstParagraphAndDropsTheOtherEmptyOnes() throws {
        let table = tbl(tr(tc(p("0000L001", "姓名")), tc(p("0000E001") + p("0000E002"))))
        let out = try apply(table, FormPlan(fieldSize: FieldSize(halfPoints: 24),
                                            tableDefaults: [try spec("0000L001=col:2")])).documentXML
        XCTAssertTrue(try TestXML.paragraphXML("0000E001", in: out).contains("<w:jc w:val=\"left\"/>"))
        XCTAssertFalse(TestXML.string(out).contains("0000E002"), "the other empty paragraph is cleaned up")
    }

    func testEveryFilledParagraphOfAFillCellIsTidied() throws {
        let table = tbl(tr(tc(p("0000L001", "地址")),
                           tc(p("0000F001", "第一行", size: 20) + p(nil) + p("0000F002", "第二行", size: 20))))
        let out = try apply(table, FormPlan(tableDefaults: [try spec("0000L001=col:2")])).documentXML
        for id in ["0000F001", "0000F002"] {
            XCTAssertTrue(try TestXML.paragraphXML(id, in: out).contains("<w:jc w:val=\"left\"/>"), id)
        }
        let index = try XMLTagIndex(out)
        XCTAssertEqual(index.elements(named: "w:p").count, 3, "label, two filled lines; the empty paragraph went")
    }

    func testAContinuationCellIsNotAFillCell() throws {
        let table = tbl(
            tr(tc(p("0000L001", "備註")), tc(p("0000F001", "見附件", size: 20), vMerge: "restart")),
            tr(tc(p("0000L002", "")), tc(p("0000C001"), vMerge: "")))
        let before = TestXML.document(table + TestXML.bodySection)
        let result = try apply(table, FormPlan(tableDefaults: [try spec("0000L001=col:2")]))
        XCTAssertTrue(try TestXML.paragraphXML("0000F001", in: result.documentXML).contains("<w:jc w:val=\"left\"/>"))
        XCTAssertEqual(try cellXML("0000C001", in: result.documentXML), try cellXML("0000C001", in: before))
        XCTAssertEqual(result.tableDefaultsReports, [TableDefaultsReport(anchor: "0000L001", fillCells: 1, partialCells: [])])
    }

    func testAnAnchorInANestedTableNamesThatTable() throws {
        let nested = tbl(tr(tc(p("0000N001", "內標")), tc(p("0000N002", "內填", size: 20))))
        let outer = tbl(tr(tc(p("0000O001", "外標")), tc(p("0000O002", "外填", size: 20) + nested + p(nil))))
        let inner = try apply(outer, FormPlan(tableDefaults: [try spec("0000N001=col:2")])).documentXML
        XCTAssertTrue(try TestXML.paragraphXML("0000N002", in: inner).contains("<w:jc w:val=\"left\"/>"))
        XCTAssertFalse(try TestXML.paragraphXML("0000O002", in: inner).contains("w:jc"))

        let outerOnly = try apply(outer, FormPlan(tableDefaults: [try spec("0000O001=col:2")])).documentXML
        XCTAssertTrue(try TestXML.paragraphXML("0000O002", in: outerOnly).contains("<w:jc w:val=\"left\"/>"))
        for id in ["0000N001", "0000N002"] {
            XCTAssertFalse(try TestXML.paragraphXML(id, in: outerOnly).contains("w:jc"), "\(id) belongs to the nested table")
        }
    }

    func testAnExplicitFieldAndTableFieldsShareOneSize() throws {
        let result = try apply(exampleTable, FormPlan(fields: ["0000F003", "0000F001"],
                                                      tableDefaults: [try spec("0000L001=col:2,4")]))
        XCTAssertEqual(result.fieldSize, FieldSize(halfPoints: 20), "the mode of 28, 20, 20")
        XCTAssertTrue(try TestXML.paragraphXML("0000F003", in: result.documentXML).contains("<w:sz w:val=\"20\"/>"))
    }

    func testAGivenFieldSizeAppliesToTableFields() throws {
        let out = try apply(exampleTable, FormPlan(fieldSize: FieldSize(halfPoints: 24),
                                                   tableDefaults: [try spec("0000L001=col:2,4")])).documentXML
        XCTAssertTrue(try TestXML.paragraphXML("0000F001", in: out).contains("<w:sz w:val=\"24\"/>"))
    }

    // MARK: refusals

    func testAColumnOrRowBeyondTheTableIsRefused() {
        for raw in ["0000L001=col:5", "0000L001=col:2,5-", "0000L001=row:4", "0000L001=col:2/row:2-9"] {
            guard case .tableSelectionOutOfRange(let id, _)? = refusal(exampleTable, FormPlan(tableDefaults: [try! spec(raw)])) else {
                XCTFail(raw)
                continue
            }
            XCTAssertEqual(id, "0000L001", raw)
        }
    }

    func testASelectionWithoutAnyFillCellIsRefused() throws {
        // The address spans columns 2–4, so naming 3–4 covers only part of it.
        XCTAssertEqual(refusal(exampleTable, FormPlan(tableDefaults: [try spec("0000L001=col:3-4/row:3")])),
                       .noFillCells("0000L001"))
    }

    func testEachSelectionMustFindAFillCellOfItsOwn() throws {
        XCTAssertEqual(refusal(exampleTable, FormPlan(tableDefaults: [
            try spec("0000L001=col:2,4"), try spec("0000L003=col:3-4/row:3"),
        ])), .noFillCells("0000L003"))
    }

    /// Verify R1 (logic, devil's advocate): an empty fill cell whose first
    /// paragraph has no id holds nothing to tidy, so it is left alone and
    /// listed instead of stopping the whole table; so is a cell with no paragraph.
    func testFillCellsWithoutAnAddressableParagraphAreLeftAloneAndListed() throws {
        let nested = tbl(tr(tc(p("0000N001", "內層"))))
        let table = tbl(
            tr(tc(p("0000L001", "姓名")), tc(p("0000F001", "王小明", size: 20))),
            tr(tc(p("0000L002", "電話")), tc(p(nil))),
            tr(tc(p("0000L003", "備註")), tc(nested)))
        let before = TestXML.document(table + TestXML.bodySection)
        let result = try apply(table, FormPlan(tableDefaults: [try spec("0000L001=col:2")]))
        XCTAssertTrue(try TestXML.paragraphXML("0000F001", in: result.documentXML).contains("<w:jc w:val=\"left\"/>"))
        let index = try XMLTagIndex(result.documentXML)
        let original = try XMLTagIndex(before)
        let cells = index.elements(named: "w:tc"), originalCells = original.elements(named: "w:tc")
        XCTAssertEqual(index.elementString(cells[3]), original.elementString(originalCells[3]), "the empty cell is unchanged")
        XCTAssertFalse(try TestXML.paragraphXML("0000N001", in: result.documentXML).contains("w:jc"), "the nested table is untouched")
        XCTAssertEqual(result.tableDefaultsReports, [
            TableDefaultsReport(anchor: "0000L001", fillCells: 1, partialCells: [], skippedCells: ["r2c2", "r3c2"]),
        ])
    }

    func testASelectionNoneOfWhoseFillCellsCanBeTidiedIsRefused() throws {
        let table = tbl(tr(tc(p("0000L001", "電話")), tc(p(nil))))
        XCTAssertEqual(refusal(table, FormPlan(fieldSize: FieldSize(halfPoints: 24), tableDefaults: [try spec("0000L001=col:2")])),
                       .noTidyableFillCells("0000L001", cells: ["r1c2"]))
    }

    func testAFillParagraphWithoutAParaIdIsRefused() throws {
        let table = tbl(tr(tc(p("0000L001", "姓名")), tc(p(nil, "王小明", size: 20))))
        XCTAssertEqual(refusal(table, FormPlan(tableDefaults: [try spec("0000L001=col:2")])),
                       .fillCellWithoutParaId("0000L001", cell: "r1c2"))
    }

    func testAnUnreadableGridIsRefusedByTheCallersId() throws {
        let table = tbl(tr(tc(p("0000L001", "姓名"), extra: "<w:hMerge w:val=\"restart\"/>"), tc(p("0000F001", "值"))))
        guard case .tableGridUnreadable(let id, _)? = refusal(table, FormPlan(tableDefaults: [try spec("0000L001=col:2")])) else {
            return XCTFail("expected tableGridUnreadable")
        }
        XCTAssertEqual(id, "0000L001")
    }

    func testAnAnchorOutsideAnyTableIsRefused() throws {
        XCTAssertEqual(refusal(p("0000B001", "本文") + exampleTable, FormPlan(tableDefaults: [try spec("0000B001=col:2")])),
                       .tableDefaultsNotInTable("0000B001"))
    }

    func testAnAnchorInATextBoxIsRefused() throws {
        let textBox = "<w:r><w:drawing><wp:inline><w:txbxContent>"
            + p("0000X002", "方塊內") + "</w:txbxContent></wp:inline></w:drawing></w:r>"
        let table = tbl(tr(tc(TestXML.paragraph("0000X001", TestXML.run("標籤") + textBox)), tc(p("0000F001", "值"))))
        XCTAssertEqual(refusal(table, FormPlan(tableDefaults: [try spec("0000X002=col:2")])),
                       .tableDefaultsInTextBox("0000X002"))
    }

    func testRemovingATableFieldIsAConflict() throws {
        guard case .conflictingOperations(let id, _)? = refusal(exampleTable, FormPlan(
            removals: ["0000F001"], tableDefaults: [try spec("0000L001=col:2,4")])) else {
            return XCTFail("expected a conflict")
        }
        XCTAssertEqual(id, "0000F001")
    }

    func testRemovingTheSameTableIsAConflictNamedByTheAnchor() throws {
        let body = p("0000A001", "前") + exampleTable + p("0000A002", "後")
        guard case .conflictingOperations(let id, _)? = refusal(body, FormPlan(
            removedTables: ["0000F002"], tableDefaults: [try spec("0000L001=col:2,4")])) else {
            return XCTFail("expected a conflict")
        }
        XCTAssertEqual(id, "0000L001")
    }

    func testTruncatingAwayTheTableIsAConflict() throws {
        let body = p("0000A001", "前") + p("0000A002", "截斷點") + exampleTable
        guard case .conflictingOperations? = refusal(body, FormPlan(
            truncateFrom: "0000A002", tableDefaults: [try spec("0000L001=col:2,4")])) else {
            return XCTFail("expected a conflict")
        }
    }

    // MARK: classify --grid

    func testClassifyWithCellsGivesEachCellParagraphItsGridPosition() throws {
        let doc = TestXML.document(p("0000B001", "本文") + exampleTable + TestXML.bodySection)
        let classified = try FormClassifier.classify(documentXML: doc, numberingXML: nil, withCells: true)
        XCTAssertTrue(classified.contains { $0.paraId == "0000B001" })
        XCTAssertNil(position("0000B001", in: classified), "a body paragraph has no cell")
        XCTAssertEqual(position("0000T001", in: classified), .cell(table: 1, rows: 1...1, columns: 1...4))
        XCTAssertEqual(position("0000F002", in: classified), .cell(table: 1, rows: 2...2, columns: 4...4))
        XCTAssertEqual(position("0000F003", in: classified), .cell(table: 1, rows: 3...3, columns: 2...4))
        XCTAssertEqual(position("0000F003", in: classified)?.description, "t1:r3c2-4")

        let plain = try FormClassifier.classify(documentXML: doc, numberingXML: nil)
        XCTAssertTrue(plain.allSatisfy { $0.cell == nil }, "positions are computed only on request")
    }

    func testClassifyReportsTheMergedCellForAContinuationAndMarksUnreadableTables() throws {
        let merged = tbl(tr(tc(p("0000A001", "上"), vMerge: "restart")), tr(tc(p("0000A002"), vMerge: "")))
        let broken = tbl(tr(tc(p("0000Z001", "壞"), extra: "<w:hMerge/>")))
        let classified = try FormClassifier.classify(documentXML: TestXML.document(merged + p("0000B001", "間") + broken
                                                                                   + TestXML.bodySection),
                                                     numberingXML: nil, withCells: true)
        XCTAssertEqual(position("0000A002", in: classified), .cell(table: 1, rows: 1...2, columns: 1...1))
        XCTAssertEqual(position("0000A002", in: classified)?.description, "t1:r1-2c1")
        XCTAssertEqual(position("0000Z001", in: classified), .unreadableTable(table: 2))
        XCTAssertEqual(position("0000Z001", in: classified)?.description, "t2:?")
    }

    func testTheExampleIdsAreAllPresent() throws {
        // Guards the fixture itself: every id the tests above use is in it once.
        let index = try XMLTagIndex(TestXML.document(exampleTable))
        for id in exampleIds {
            guard case .found = FormLocator.paragraph(withId: id, in: index) else { return XCTFail(id) }
        }
    }
}
