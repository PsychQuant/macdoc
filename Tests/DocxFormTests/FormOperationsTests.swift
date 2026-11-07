// FormOperationsTests.swift — the operations of `word form apply` (#249).

import XCTest
@testable import DocxForm

final class FormOperationsTests: XCTestCase {
    private func apply(_ body: String, _ plan: FormPlan, numbering: [UInt8]? = nil) throws -> [UInt8] {
        try plan.apply(toDocumentXML: TestXML.document(body)).documentXML
    }

    // MARK: Table field normalization makes designated fields uniform

    func testFieldWithStyleIndentAndDistributedAlignment() throws {
        let pPr = "<w:pPr><w:pStyle w:val=\"a3\"/><w:ind w:firstLine=\"480\"/><w:jc w:val=\"distribute\"/>"
            + "<w:rPr><w:rFonts w:eastAsia=\"標楷體\"/><w:sz w:val=\"18\"/></w:rPr></w:pPr>"
        let field = TestXML.paragraph("0000F001", pPr: pPr, TestXML.run("王小明", rPr: "<w:rPr><w:sz w:val=\"18\"/><w:lang w:eastAsia=\"zh-TW\"/></w:rPr>"))
        let tcPr = "<w:tcPr><w:tcW w:w=\"2000\" w:type=\"dxa\"/><w:vAlign w:val=\"top\"/><w:hideMark/></w:tcPr>"
        let out = try apply(TestXML.table([TestXML.cell(field, tcPr: tcPr)]),
                            FormPlan(fields: ["0000F001"], fieldSize: try FieldSize.parse(points: "12")))
        let paragraph = try TestXML.paragraphXML("0000F001", in: out)
        XCTAssertFalse(paragraph.contains("w:pStyle"))
        XCTAssertFalse(paragraph.contains("w:ind"))
        XCTAssertFalse(paragraph.contains("distribute"))
        XCTAssertEqual(try TestXML.childNames(of: "w:pPr", in: paragraph), ["w:jc", "w:rPr"])
        XCTAssertTrue(paragraph.contains("<w:jc w:val=\"left\"/>"))
        // Mark and run both sized, szCs right after sz and before w:lang.
        XCTAssertEqual(try TestXML.childNames(of: "w:rPr", in: paragraph), ["w:rFonts", "w:sz", "w:szCs"])
        let run = try XMLTagIndex(paragraph)
        let runRPr = run.elements(named: "w:rPr").last!
        XCTAssertEqual(run.children(of: runRPr).map { run.tags[$0].name }, ["w:sz", "w:szCs", "w:lang"])
        XCTAssertEqual(paragraph.components(separatedBy: "<w:sz w:val=\"24\"/><w:szCs w:val=\"24\"/>").count - 1, 2)
        // Cell vertically centred, vAlign before hideMark, old value gone.
        let cell = try XMLTagIndex(out)
        let tcPrIndex = cell.elements(named: "w:tcPr").first!
        XCTAssertEqual(cell.children(of: tcPrIndex).map { cell.tags[$0].name }, ["w:tcW", "w:vAlign", "w:hideMark"])
        XCTAssertTrue(TestXML.string(out).contains("<w:vAlign w:val=\"center\"/>"))
        XCTAssertFalse(TestXML.string(out).contains("w:val=\"top\""))
    }

    func testFieldWithoutPropertiesGetsThemInSchemaOrder() throws {
        let field = TestXML.paragraph("0000F002", TestXML.run("值"))
        let out = try apply(TestXML.table([TestXML.cell(field, tcPr: "")]),
                            FormPlan(fields: ["0000F002"], fieldSize: FieldSize(halfPoints: 22)))
        let paragraph = try TestXML.paragraphXML("0000F002", in: out)
        XCTAssertTrue(paragraph.hasPrefix("<w:p w14:paraId=\"0000F002\"><w:pPr><w:jc w:val=\"left\"/><w:rPr><w:sz w:val=\"22\"/>"))
        XCTAssertTrue(paragraph.contains("<w:r><w:rPr><w:sz w:val=\"22\"/><w:szCs w:val=\"22\"/></w:rPr><w:t"))
        XCTAssertTrue(TestXML.string(out).contains("<w:tc><w:tcPr><w:vAlign w:val=\"center\"/></w:tcPr><w:p"))
    }

    func testEmptySiblingIsRemovedButADrawingParagraphIsKept() throws {
        let field = TestXML.paragraph("0000F003", TestXML.run("值", rPr: "<w:rPr><w:sz w:val=\"24\"/></w:rPr>"))
        let empty = TestXML.paragraph("0000E001", "<w:r><w:rPr><w:sz w:val=\"24\"/></w:rPr></w:r>")
        let drawing = TestXML.paragraph("0000D001", "<w:r><w:drawing><wp:inline/></w:drawing></w:r>")
        let sectionBreak = TestXML.paragraph("0000S001", pPr: "<w:pPr>\(TestXML.bodySection)</w:pPr>")
        let out = try apply(TestXML.table([TestXML.cell(field + empty + drawing + sectionBreak)]),
                            FormPlan(fields: ["0000F003"]))
        let xml = TestXML.string(out)
        XCTAssertFalse(xml.contains("0000E001"), "empty sibling removed")
        XCTAssertTrue(xml.contains("0000D001"), "drawing paragraph kept")
        XCTAssertTrue(xml.contains("0000S001"), "section-break paragraph kept")
    }

    /// Empty is a closed list (empty runs, proofErr); bookmarks and tabs are content.
    func testOnlyProvablyEmptySiblingsAreRemoved() throws {
        let field = TestXML.paragraph("0000F010", TestXML.run("值", rPr: "<w:rPr><w:sz w:val=\"24\"/></w:rPr>"))
        let empty = TestXML.paragraph("0000E010", "<w:proofErr w:type=\"spellStart\"/><w:r><w:rPr/><w:t></w:t><w:lastRenderedPageBreak/></w:r>")
        let bookmark = TestXML.paragraph("0000E011", "<w:bookmarkStart w:id=\"0\" w:name=\"x\"/><w:bookmarkEnd w:id=\"0\"/>")
        let tab = TestXML.paragraph("0000E012", "<w:r><w:tab/></w:r>")
        let deleted = TestXML.paragraph("0000E013", "<w:del w:id=\"1\" w:author=\"a\"><w:r><w:delText>舊</w:delText></w:r></w:del>")
        let out = TestXML.string(try apply(TestXML.table([TestXML.cell(field + empty + bookmark + tab + deleted)]),
                                           FormPlan(fields: ["0000F010"])))
        XCTAssertFalse(out.contains("0000E010"))
        for kept in ["0000E011", "0000E012", "0000E013"] { XCTAssertTrue(out.contains(kept), kept) }
    }

    func testCellWithAContentControlKeepsItsSiblings() throws {
        let field = TestXML.paragraph("0000F020", TestXML.run("值", rPr: "<w:rPr><w:sz w:val=\"24\"/></w:rPr>"))
        let wrapped = "<w:sdt><w:sdtPr/><w:sdtContent>" + TestXML.paragraph("0000F021", TestXML.run("控制項")) + "</w:sdtContent></w:sdt>"
        let out = TestXML.string(try apply(TestXML.table([TestXML.cell(field + wrapped + TestXML.paragraph("0000E020"))]),
                                           FormPlan(fields: ["0000F020"])))
        XCTAssertTrue(out.contains("0000E020"), "cleanup skipped when the cell holds a content control")
    }

    func testCellWithNestedTableKeepsItsSiblings() throws {
        let field = TestXML.paragraph("0000F004", TestXML.run("值", rPr: "<w:rPr><w:sz w:val=\"24\"/></w:rPr>"))
        let empty = TestXML.paragraph("0000E002")
        let nested = TestXML.table([TestXML.cell(TestXML.paragraph("0000N001", TestXML.run("內層")))])
        let out = try apply(TestXML.table([TestXML.cell(field + empty + nested + TestXML.paragraph(nil))]),
                            FormPlan(fields: ["0000F004"]))
        XCTAssertTrue(TestXML.string(out).contains("0000E002"))
    }

    func testFieldOutsideATableIsRefused() {
        let body = TestXML.paragraph("0000F005", TestXML.run("本文", rPr: "<w:rPr><w:sz w:val=\"24\"/></w:rPr>"))
        XCTAssertThrowsError(try apply(body, FormPlan(fields: ["0000F005"]))) {
            XCTAssertEqual($0 as? FormError, .notInTableCell("0000F005"))
        }
    }

    /// The size goes before extension elements, which Word writes last.
    func testFieldSizeIsInsertedBeforeExtensionElements() throws {
        // w:b precedes the size, so only the extension element can be a follower.
        let rPr = "<w:rPr><w:b/><w14:ligatures w14:val=\"standard\"/></w:rPr>"
        let field = TestXML.paragraph("0000F0E1", TestXML.run("值", rPr: rPr))
        let out = try apply(TestXML.table([TestXML.cell(field)]),
                            FormPlan(fields: ["0000F0E1"], fieldSize: try FieldSize.parse(points: "12")))
        let paragraph = try TestXML.paragraphXML("0000F0E1", in: out)
        let index = try XMLTagIndex(paragraph)
        let runRPr = index.elements(named: "w:rPr").last!
        XCTAssertEqual(index.children(of: runRPr).map { index.tags[$0].name }, ["w:b", "w:sz", "w:szCs", "w14:ligatures"])
    }

    /// A paragraph in a text box anchored in a cell is not a field of that
    /// cell; styling the outer cell would change the wrong cell.
    func testFieldInsideATextBoxInACellIsRefused() {
        let textBox = "<w:r><w:drawing><wp:inline><w:txbxContent>"
            + TestXML.paragraph("0000F0B2", TestXML.run("方塊內")) + "</w:txbxContent></wp:inline></w:drawing></w:r>"
        let body = TestXML.table([TestXML.cell(TestXML.paragraph("0000F0B1", TestXML.run("標籤") + textBox))])
        XCTAssertThrowsError(try apply(body, FormPlan(fields: ["0000F0B2"], fieldSize: try FieldSize.parse(points: "12")))) {
            XCTAssertEqual($0 as? FormError, .notInTableCell("0000F0B2"))
        }
    }

    // MARK: The default field size is the most common designated size

    private func fieldTable(_ sizes: [Int?]) -> (body: String, ids: [String]) {
        var cells: [String] = []
        var ids: [String] = []
        for (k, size) in sizes.enumerated() {
            let id = String(format: "0000A%03d", k)
            ids.append(id)
            let rPr = size.map { "<w:rPr><w:sz w:val=\"\($0)\"/></w:rPr>" } ?? ""
            cells.append(TestXML.cell(TestXML.paragraph(id, TestXML.run("值\(k)", rPr: rPr))))
        }
        return (TestXML.table(cells), ids)
    }

    func testSizeResolutionTable() throws {
        // (collected sizes, --field-size, expected half-points or nil for refusal)
        let rows: [([Int?], String?, Int?)] = [
            ([18, 24, 24], nil, 24),
            ([18, 24], nil, 24),
            ([22, 22, 18], "10.5", 21),
            ([nil], nil, nil),
        ]
        for (sizes, given, expected) in rows {
            let (body, ids) = fieldTable(sizes)
            let plan = FormPlan(fields: ids, fieldSize: try given.map { try FieldSize.parse(points: $0) })
            if let expected {
                let result = try plan.apply(toDocumentXML: TestXML.document(body))
                XCTAssertEqual(result.fieldSize?.halfPoints, expected, "\(sizes) \(String(describing: given))")
                XCTAssertEqual(result.fieldSizeWasDerived, given == nil)
                for id in ids {
                    XCTAssertTrue(try TestXML.paragraphXML(id, in: result.documentXML)
                        .contains("<w:sz w:val=\"\(expected)\"/>"), id)
                }
            } else {
                XCTAssertThrowsError(try plan.apply(toDocumentXML: TestXML.document(body))) {
                    XCTAssertEqual($0 as? FormError, .noFieldSize)
                }
            }
        }
        XCTAssertThrowsError(try FieldSize.parse(points: "10.3")) {
            XCTAssertEqual($0 as? FormError, .invalidFieldSize("10.3"))
        }
    }

    func testFieldSizeParsingBounds() throws {
        XCTAssertEqual(try FieldSize.parse(points: "1").halfPoints, 2)
        XCTAssertEqual(try FieldSize.parse(points: "1638").halfPoints, 3276)
        for bad in ["0.5", "1638.5", "-12", "12pt", "", "1e1", "abc", "12.5.3", "1..5", ".", "12.", ".5"] {
            XCTAssertThrowsError(try FieldSize.parse(points: bad), bad)
        }
        XCTAssertEqual(FieldSize(halfPoints: 21).pointsDescription, "10.5 pt")
        XCTAssertEqual(FieldSize(halfPoints: 24).pointsDescription, "12 pt")
    }

    func testFieldWithoutTextContributesItsMarkSize() throws {
        let mark = "<w:pPr><w:rPr><w:sz w:val=\"20\"/></w:rPr></w:pPr>"
        let body = TestXML.table([TestXML.cell(TestXML.paragraph("0000A100", pPr: mark))])
        let result = try FormPlan(fields: ["0000A100"]).apply(toDocumentXML: TestXML.document(body))
        XCTAssertEqual(result.fieldSize?.halfPoints, 20)
    }

    // MARK: Box glyphs are drawn in one font

    func testBoxAfterLatinTextInOneRun() throws {
        let rPr = "<w:rPr><w:rFonts w:ascii=\"Times New Roman\" w:hAnsi=\"Times New Roman\"/><w:sz w:val=\"24\"/></w:rPr>"
        let body = TestXML.paragraph("0000C001", TestXML.run(")  \u{25A1}", rPr: rPr))
        let out = try apply(body, FormPlan(checkboxFont: "標楷體"))
        let paragraph = try TestXML.paragraphXML("0000C001", in: out)
        let index = try XMLTagIndex(paragraph)
        let runs = index.elements(named: "w:r")
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(FormLocator.runText(runs[0], in: index), ")  ")
        XCTAssertTrue(index.elementString(runs[0]).contains("Times New Roman"))
        XCTAssertTrue(index.elementString(runs[0]).contains("xml:space=\"preserve\""))
        XCTAssertEqual(FormLocator.runText(runs[1], in: index), "\u{25A1}")
        let boxRun = index.elementString(runs[1])
        XCTAssertTrue(boxRun.contains("<w:rFonts w:ascii=\"標楷體\" w:hAnsi=\"標楷體\" w:eastAsia=\"標楷體\" w:cs=\"標楷體\"/>"))
        XCTAssertFalse(boxRun.contains("Times New Roman"))
        XCTAssertTrue(boxRun.contains("<w:sz w:val=\"24\"/>"))
        XCTAssertEqual(TestXML.string(Array(try TestXML.text("0000C001", in: out).utf8)), ")  \u{25A1}")
    }

    /// A native checkbox content control redraws its glyph from the w14 state
    /// fonts, so its run is left alone and counted.
    func testNativeCheckboxControlIsLeftAloneAndCounted() throws {
        let control = "<w:sdt><w:sdtPr><w14:checkbox><w14:checked w14:val=\"0\"/>"
            + "<w14:checkedState w14:val=\"2612\" w14:font=\"MS Gothic\"/><w14:uncheckedState w14:val=\"2610\" w14:font=\"MS Gothic\"/>"
            + "</w14:checkbox></w:sdtPr><w:sdtContent>"
            + TestXML.run("\u{2610}", rPr: "<w:rPr><w:rFonts w:ascii=\"MS Gothic\" w:hint=\"eastAsia\"/></w:rPr>")
            + "</w:sdtContent></w:sdt>"
        let body = TestXML.paragraph("0000C0C1", control + TestXML.run(" 同意"))
            + TestXML.paragraph("0000C0C2", TestXML.run("\u{25A1} 一般方框"))
        let result = try FormPlan(checkboxFont: "標楷體").apply(toDocumentXML: TestXML.document(body))
        XCTAssertEqual(result.skippedCheckboxRuns, 1)
        XCTAssertTrue(try TestXML.paragraphXML("0000C0C1", in: result.documentXML).contains("w:hint=\"eastAsia\""))
        XCTAssertTrue(try TestXML.paragraphXML("0000C0C2", in: result.documentXML).contains("w:eastAsia=\"標楷體\""))
    }

    /// The font goes before extension elements, which Word writes last.
    func testCheckboxFontIsInsertedBeforeExtensionElements() throws {
        let body = TestXML.paragraph("0000C0E1", TestXML.run("\u{25A1}", rPr: "<w:rPr><w14:ligatures w14:val=\"standard\"/></w:rPr>"))
        let out = try apply(body, FormPlan(checkboxFont: "標楷體"))
        let paragraph = try TestXML.paragraphXML("0000C0E1", in: out)
        XCTAssertEqual(try TestXML.childNames(of: "w:rPr", in: paragraph), ["w:rFonts", "w14:ligatures"])
    }

    func testGlyphOnlyRunKeepsItsTextElementAndGetsTheFont() throws {
        let body = TestXML.paragraph("0000C002", TestXML.run("\u{25A0}\u{25A1}"))
        let out = try apply(body, FormPlan(checkboxFont: "標楷體"))
        let paragraph = try TestXML.paragraphXML("0000C002", in: out)
        XCTAssertEqual(paragraph.components(separatedBy: "<w:r>").count - 1, 1)
        XCTAssertTrue(paragraph.contains("<w:rPr><w:rFonts w:ascii=\"標楷體\""))
    }

    func testRunWithOtherContentIsSkippedAndCounted() throws {
        let run = "<w:r><w:tab/><w:t>\u{25A1}</w:t></w:r>"
        let body = TestXML.paragraph("0000C003", run)
        let result = try FormPlan(checkboxFont: "標楷體").apply(toDocumentXML: TestXML.document(body))
        XCTAssertEqual(result.skippedCheckboxRuns, 1)
        XCTAssertEqual(TestXML.string(result.documentXML), TestXML.string(TestXML.document(body)))
    }

    func testCDATATextIsTakenLiterally() throws {
        let body = TestXML.paragraph("0000C006", "<w:r><w:t><![CDATA[A\u{25A1}B]]></w:t></w:r>")
        let out = try apply(body, FormPlan(checkboxFont: "標楷體"))
        let index = try XMLTagIndex(out)
        let runs = index.elements(named: "w:r")
        XCTAssertEqual(runs.map { FormLocator.runText($0, in: index) }, ["A", "\u{25A1}", "B"])
        XCTAssertFalse(TestXML.string(out).contains("CDATA"))
    }

    func testSplitRunWithTrackedFormattingIsLeftAloneAndCounted() throws {
        let run = "<w:r><w:rPr><w:b/><w:rPrChange w:id=\"8\" w:author=\"a\"><w:rPr/></w:rPrChange></w:rPr><w:t>A\u{25A1}B</w:t></w:r>"
        let body = TestXML.paragraph("0000C010", run)
        let result = try FormPlan(checkboxFont: "標楷體").apply(toDocumentXML: TestXML.document(body))
        XCTAssertEqual(result.skippedCheckboxRuns, 1)
        XCTAssertEqual(TestXML.string(result.documentXML).components(separatedBy: "<w:rPrChange").count - 1, 1)
        XCTAssertEqual(TestXML.string(result.documentXML), TestXML.string(TestXML.document(body)))
    }

    func testFontNameIsEscaped() throws {
        let body = TestXML.paragraph("0000C004", TestXML.run("\u{25A1}"))
        let out = try apply(body, FormPlan(checkboxFont: "A&B \"C\""))
        XCTAssertTrue(TestXML.string(out).contains("w:ascii=\"A&amp;B &quot;C&quot;\""))
    }

    func testEmptyFontIsRefused() {
        XCTAssertThrowsError(try apply(TestXML.paragraph("0000C005"), FormPlan(checkboxFont: ""))) {
            XCTAssertEqual($0 as? FormError, .invalidFont(""))
        }
    }

    func testSplitBoxesKeepsOrder() {
        XCTAssertEqual(FormOperations.splitBoxes("a\u{25A1}\u{25A1}b\u{25A0}"), [
            .init(text: "a", isBox: false), .init(text: "\u{25A1}\u{25A1}", isBox: true),
            .init(text: "b", isBox: false), .init(text: "\u{25A0}", isBox: true),
        ])
    }

    // MARK: A box that is a list bullet can be ticked

    func testTickABulletedOption() throws {
        let body = TestXML.paragraph("0000T001", pPr: TestXML.numbered,
                                     TestXML.run("第一個選項", rPr: "<w:rPr><w:sz w:val=\"24\"/></w:rPr>"))
        let out = try apply(body, FormPlan(tickList: ["0000T001"]))
        let paragraph = try TestXML.paragraphXML("0000T001", in: out)
        XCTAssertFalse(paragraph.contains("w:numPr"))
        XCTAssertEqual(try TestXML.text("0000T001", in: out), "\u{25A0}第一個選項")
        XCTAssertTrue(paragraph.contains("<w:r><w:rPr><w:sz w:val=\"24\"/></w:rPr><w:t>\u{25A0}</w:t></w:r>"))
    }

    func testTickWithoutTextRunsUsesTheCleanedMark() throws {
        let pPr = "<w:pPr><w:numPr><w:numId w:val=\"3\"/></w:numPr><w:rPr><w:ins w:id=\"1\" w:author=\"x\"/><w:sz w:val=\"20\"/></w:rPr></w:pPr>"
        let out = try apply(TestXML.paragraph("0000T002", pPr: pPr), FormPlan(tickList: ["0000T002"]))
        let paragraph = try TestXML.paragraphXML("0000T002", in: out)
        XCTAssertTrue(paragraph.contains("<w:r><w:rPr><w:sz w:val=\"20\"/></w:rPr><w:t>\u{25A0}</w:t></w:r>"))
        XCTAssertEqual(paragraph.components(separatedBy: "w:ins").count - 1, 1, "only the mark keeps w:ins")
    }

    func testTickDoesNotCopyTrackedFormatting() throws {
        let rPr = "<w:rPr><w:b/><w:rPrChange w:id=\"9\" w:author=\"a\"><w:rPr/></w:rPrChange></w:rPr>"
        let body = TestXML.paragraph("0000T010", pPr: TestXML.numbered, TestXML.run("選項", rPr: rPr))
        let out = TestXML.string(try apply(body, FormPlan(tickList: ["0000T010"])))
        XCTAssertTrue(out.contains("<w:r><w:rPr><w:b/></w:rPr><w:t>\u{25A0}</w:t></w:r>"))
        XCTAssertEqual(out.components(separatedBy: "<w:rPrChange").count - 1, 1, "the original run keeps its own")
    }

    func testTickWithNumberingIdZeroIsRefused() {
        let pPr = "<w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"0\"/></w:numPr></w:pPr>"
        XCTAssertThrowsError(try apply(TestXML.paragraph("0000T004", pPr: pPr, TestXML.run("x")), FormPlan(tickList: ["0000T004"]))) {
            XCTAssertEqual($0 as? FormError, .noOwnNumbering("0000T004"))
        }
    }

    func testTickWithoutNumberingIsRefused() {
        XCTAssertThrowsError(try apply(TestXML.paragraph("0000T003", TestXML.run("x")), FormPlan(tickList: ["0000T003"]))) {
            XCTAssertEqual($0 as? FormError, .noOwnNumbering("0000T003"))
        }
    }

    // MARK: Inserted paragraphs inherit the anchor's format

    func testTwoParagraphsAfterOneAnchor() throws {
        let pPr = "<w:pPr><w:pStyle w:val=\"Body\"/><w:numPr><w:numId w:val=\"3\"/></w:numPr><w:ind w:left=\"480\"/>\(TestXML.bodySection)</w:pPr>"
        let anchor = TestXML.paragraph("0000I001", pPr: pPr, TestXML.run("錨點", rPr: "<w:rPr><w:rFonts w:eastAsia=\"標楷體\"/></w:rPr>"))
        let after = TestXML.paragraph("0000I002", TestXML.run("後面"))
        let out = try apply(anchor + after, FormPlan(insertions: [
            FormInsertion(anchor: "0000I001", text: "第一段"),
            FormInsertion(anchor: "0000I001", text: "第二段"),
        ]))
        let index = try XMLTagIndex(out)
        let paragraphs = index.elements(named: "w:p")
        XCTAssertEqual(paragraphs.map { FormClassifier.ownText(of: $0, in: index) }, ["錨點", "第一段", "第二段", "後面"])
        for inserted in paragraphs[1...2] {
            let xml = index.elementString(inserted)
            XCTAssertTrue(xml.contains("<w:pStyle w:val=\"Body\"/>"))
            XCTAssertTrue(xml.contains("<w:ind w:left=\"480\"/>"))
            XCTAssertTrue(xml.contains("標楷體"))
            XCTAssertFalse(xml.contains("w:numPr"))
        }
        // The anchor ended a section; the break now ends the inserted
        // paragraphs, so they stay in the anchor's section.
        XCTAssertFalse(index.elementString(paragraphs[0]).contains("w:sectPr"))
        XCTAssertFalse(index.elementString(paragraphs[1]).contains("w:sectPr"))
        XCTAssertTrue(index.elementString(paragraphs[2]).contains(TestXML.bodySection))
        XCTAssertEqual(index.elements(named: "w:sectPr").count, 1)
    }

    /// Insert after a section break, then cut what follows: the inserted
    /// paragraph is the kept content's last block and carries the break, so
    /// the kept-break rule still applies and no extra final section remains.
    func testInsertAfterABreakThenTruncateKeepsOneSection() throws {
        let s1 = "<w:sectPr><w:pgSz w:w=\"16838\" w:h=\"11906\" w:orient=\"landscape\"/></w:sectPr>"
        let body = TestXML.paragraph("0000I010", pPr: "<w:pPr>\(s1)</w:pPr>", TestXML.run("錨點"))
            + TestXML.paragraph("0000I011", TestXML.run("下一份")) + TestXML.bodySection
        let out = try apply(body, FormPlan(insertions: [FormInsertion(anchor: "0000I010", text: "補充")],
                                           truncateFrom: "0000I011"))
        let index = try XMLTagIndex(out)
        XCTAssertEqual(index.elements(named: "w:p").map { FormClassifier.ownText(of: $0, in: index) }, ["錨點", "補充"])
        let sections = index.elements(named: "w:sectPr")
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(index.elementString(sections[0]), s1)
        XCTAssertEqual(index.tags[sections[0]].parent.map { index.tags[$0].name }, "w:body")
    }

    func testInsertDropsPageBreakAndRevisionMarks() throws {
        let pPr = "<w:pPr><w:pageBreakBefore/><w:rPr><w:ins w:id=\"7\" w:author=\"a\"/><w:sz w:val=\"20\"/></w:rPr></w:pPr>"
        let runRPr = "<w:rPr><w:b/><w:rPrChange w:id=\"8\" w:author=\"a\"><w:rPr/></w:rPrChange></w:rPr>"
        let anchor = TestXML.paragraph("0000I010", pPr: pPr, TestXML.run("錨點", rPr: runRPr))
        let out = try apply(anchor, FormPlan(insertions: [FormInsertion(anchor: "0000I010", text: "新段落")]))
        let index = try XMLTagIndex(out)
        let inserted = index.elementString(index.elements(named: "w:p")[1])
        XCTAssertFalse(inserted.contains("w:pageBreakBefore"))
        XCTAssertFalse(inserted.contains("w:ins"))
        XCTAssertFalse(inserted.contains("w:rPrChange"))
        XCTAssertTrue(inserted.contains("<w:sz w:val=\"20\"/>"))
        XCTAssertTrue(inserted.contains("<w:b/>"))
    }

    func testForbiddenCharacterIsRefused() {
        let anchor = TestXML.paragraph("0000I003", TestXML.run("錨點"))
        XCTAssertThrowsError(try apply(anchor, FormPlan(insertions: [FormInsertion(anchor: "0000I003", text: "a\u{0001}b")]))) {
            XCTAssertEqual($0 as? FormError, .invalidText("0000I003"))
        }
    }

    // MARK: Paragraphs are removed only when named

    func testRemoveOnlyParagraphOfACellIsRefused() {
        let body = TestXML.table([TestXML.cell(TestXML.paragraph("0000R001", TestXML.run("唯一")))])
        XCTAssertThrowsError(try apply(body, FormPlan(removals: ["0000R001"]))) {
            XCTAssertEqual($0 as? FormError, .onlyParagraphInCell("0000R001"))
        }
    }

    func testRemoveSectionBreakParagraphIsRefused() {
        let body = TestXML.paragraph("0000R002", pPr: "<w:pPr>\(TestXML.bodySection)</w:pPr>")
        XCTAssertThrowsError(try apply(body, FormPlan(removals: ["0000R002"]))) {
            XCTAssertEqual($0 as? FormError, .carriesSectionBreak("0000R002"))
        }
    }

    func testRemoveRefusedWhenTheCellWouldEndWithATable() {
        let nested = TestXML.table([TestXML.cell(TestXML.paragraph("0000N010", TestXML.run("內層")))])
        let body = TestXML.table([TestXML.cell(TestXML.paragraph("0000R010", TestXML.run("前")) + nested
                                               + TestXML.paragraph("0000R011", TestXML.run("後")))])
        XCTAssertThrowsError(try apply(body, FormPlan(removals: ["0000R011"]))) {
            XCTAssertEqual($0 as? FormError, .cellWouldEndWithoutParagraph("0000R011"))
        }
    }

    func testRemoveOnlyParagraphInsideAContentControlIsRefused() {
        let wrapped = "<w:sdt><w:sdtPr/><w:sdtContent>" + TestXML.paragraph("0000R030", TestXML.run("值")) + "</w:sdtContent></w:sdt>"
        let body = TestXML.table([TestXML.cell(wrapped)])
        XCTAssertThrowsError(try apply(body, FormPlan(removals: ["0000R030"]))) {
            XCTAssertEqual($0 as? FormError, .onlyParagraphInCell("0000R030"))
        }
    }

    /// A cell may end with a content control that holds a paragraph.
    func testRemoveBeforeAWrappedLastParagraphIsAllowed() throws {
        let wrapped = "<w:sdt><w:sdtPr/><w:sdtContent>" + TestXML.paragraph("0000R032", TestXML.run("值")) + "</w:sdtContent></w:sdt>"
        let body = TestXML.table([TestXML.cell(TestXML.paragraph("0000R031", TestXML.run("刪")) + wrapped)])
        let out = TestXML.string(try apply(body, FormPlan(removals: ["0000R031"])))
        XCTAssertFalse(out.contains("0000R031"))
        XCTAssertTrue(out.contains("0000R032"))
    }

    func testRemoveNamedParagraph() throws {
        let body = TestXML.paragraph("0000R003", TestXML.run("說明：請勿填寫")) + TestXML.paragraph("0000R004", TestXML.run("內容"))
        let out = try apply(body, FormPlan(removals: ["0000R003"]))
        XCTAssertFalse(TestXML.string(out).contains("0000R003"))
        XCTAssertTrue(TestXML.string(out).contains("0000R004"))
    }

    // MARK: Truncation keeps the section settings of the kept content

    private let s1 = "<w:sectPr><w:pgSz w:w=\"16838\" w:h=\"11906\" w:orient=\"landscape\"/></w:sectPr>"
    private let s2 = "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/></w:sectPr>"

    private var sectionedBody: String {
        TestXML.paragraph("0000P001", TestXML.run("P1"))
            + TestXML.paragraph("0000P002", pPr: "<w:pPr>\(s1)</w:pPr>", TestXML.run("P2"))
            + TestXML.paragraph("0000P003", TestXML.run("P3"))
            + TestXML.paragraph("0000P004", TestXML.run("P4"))
            + s2
    }

    func testCutBeforeALaterSectionBreak() throws {
        let out = try apply(sectionedBody, FormPlan(truncateFrom: "0000P002"))
        XCTAssertEqual(TestXML.string(out), TestXML.string(TestXML.document(TestXML.paragraph("0000P001", TestXML.run("P1")) + s1)))
    }

    /// Cutting at the first paragraph of a section removes that whole section:
    /// the kept content's last section break becomes the final one, so the
    /// result does not end with an empty section (an extra blank page).
    func testCutAtTheFirstParagraphOfASectionMovesTheKeptBreakToTheEnd() throws {
        let out = try apply(sectionedBody, FormPlan(truncateFrom: "0000P003"))
        let expected = TestXML.paragraph("0000P001", TestXML.run("P1"))
            + TestXML.paragraph("0000P002", pPr: "<w:pPr></w:pPr>", TestXML.run("P2")) + s1
        XCTAssertEqual(TestXML.string(out), TestXML.string(TestXML.document(expected)))
    }

    func testCutInsideTheLastSectionKeepsTheBodySection() throws {
        let out = try apply(sectionedBody, FormPlan(truncateFrom: "0000P004"))
        let expected = TestXML.paragraph("0000P001", TestXML.run("P1"))
            + TestXML.paragraph("0000P002", pPr: "<w:pPr>\(s1)</w:pPr>", TestXML.run("P2"))
            + TestXML.paragraph("0000P003", TestXML.run("P3")) + s2
        XCTAssertEqual(TestXML.string(out), TestXML.string(TestXML.document(expected)))
    }

    /// The kept break may sit in a body-level content control; it still moves.
    func testKeptBreakInsideABodyLevelContentControlMovesToTheEnd() throws {
        let wrapped = "<w:sdt><w:sdtPr/><w:sdtContent>"
            + TestXML.paragraph("0000P041", pPr: "<w:pPr><w:jc w:val=\"center\"/>\(s1)</w:pPr>", TestXML.run("控制項內"))
            + "</w:sdtContent></w:sdt>"
        let body = TestXML.paragraph("0000P040", TestXML.run("P1")) + wrapped
            + TestXML.paragraph("0000P042", TestXML.run("下一份")) + s2
        let out = try apply(body, FormPlan(truncateFrom: "0000P042"))
        let expected = TestXML.paragraph("0000P040", TestXML.run("P1")) + "<w:sdt><w:sdtPr/><w:sdtContent>"
            + TestXML.paragraph("0000P041", pPr: "<w:pPr><w:jc w:val=\"center\"/></w:pPr>", TestXML.run("控制項內"))
            + "</w:sdtContent></w:sdt>" + s1
        XCTAssertEqual(TestXML.string(out), TestXML.string(TestXML.document(expected)))
    }

    /// Any block after the kept break — here an imported chunk — belongs to
    /// the last section, so that section keeps its own settings.
    func testKeptAltChunkAfterABreakKeepsTheRemovedRangeSection() throws {
        let chunk = "<w:altChunk r:id=\"rId9\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"/>"
        let body = TestXML.paragraph("0000P060", pPr: "<w:pPr>\(s1)</w:pPr>", TestXML.run("P1")) + chunk
            + TestXML.paragraph("0000P061", TestXML.run("下一份")) + s2
        let out = try apply(body, FormPlan(truncateFrom: "0000P061"))
        // The body would end with the chunk, so an empty paragraph ends it (#250).
        let expected = TestXML.paragraph("0000P060", pPr: "<w:pPr>\(s1)</w:pPr>", TestXML.run("P1")) + chunk + "<w:p/>" + s2
        XCTAssertEqual(TestXML.string(out), TestXML.string(TestXML.document(expected)))
    }

    /// Range markers (bookmarks, comment ranges) are not blocks: the kept
    /// break is still the last block and still moves.
    func testRangeMarkersAfterTheKeptBreakDoNotStopTheMove() throws {
        let body = TestXML.paragraph("0000P070", pPr: "<w:pPr>\(s1)</w:pPr>", TestXML.run("P1"))
            + "<w:bookmarkEnd w:id=\"4\"/>"
            + TestXML.paragraph("0000P071", TestXML.run("下一份")) + s2
        let out = try apply(body, FormPlan(truncateFrom: "0000P071"))
        let expected = TestXML.paragraph("0000P070", pPr: "<w:pPr></w:pPr>", TestXML.run("P1"))
            + "<w:bookmarkEnd w:id=\"4\"/>" + s1
        XCTAssertEqual(TestXML.string(out), TestXML.string(TestXML.document(expected)))
    }

    /// With only range markers before the cut, truncation would delete every
    /// content block; it is refused like a cut at the first child.
    func testTruncateWithOnlyMarkersBeforeTheCutIsRefused() {
        let body = "<w:bookmarkStart w:id=\"1\" w:name=\"a\"/>" + TestXML.paragraph("0000P080", TestXML.run("第一段"))
            + TestXML.paragraph("0000P081", TestXML.run("第二段")) + s2
        XCTAssertThrowsError(try apply(body, FormPlan(truncateFrom: "0000P080"))) {
            XCTAssertEqual($0 as? FormError, .firstBodyChild("0000P080"))
        }
    }

    /// A table after the kept break belongs to the last section, which is not empty.
    func testKeptTableAfterABreakKeepsTheRemovedRangeSection() throws {
        let body = TestXML.paragraph("0000P050", pPr: "<w:pPr>\(s1)</w:pPr>", TestXML.run("P1"))
            + TestXML.table([TestXML.cell(TestXML.paragraph("0000P051", TestXML.run("表內")))])
            + TestXML.paragraph("0000P052", TestXML.run("下一份")) + s2
        let out = try apply(body, FormPlan(truncateFrom: "0000P052"))
        let expected = TestXML.paragraph("0000P050", pPr: "<w:pPr>\(s1)</w:pPr>", TestXML.run("P1"))
            + TestXML.table([TestXML.cell(TestXML.paragraph("0000P051", TestXML.run("表內")))]) + "<w:p/>" + s2
        // The body would end with the table, so an empty paragraph ends it (#250).
        XCTAssertEqual(TestXML.string(out), TestXML.string(TestXML.document(expected)))
    }

    /// A w:sectPr kept in w:pPrChange is revision history, not a live break.
    func testTruncateIgnoresSectionPropertiesInRevisionHistory() throws {
        let old = "<w:sectPr><w:pgSz w:w=\"1\" w:h=\"1\"/></w:sectPr>"
        let body = TestXML.paragraph("0000P020", TestXML.run("P1"))
            + TestXML.paragraph("0000P021", pPr: "<w:pPr><w:pPrChange w:id=\"3\" w:author=\"a\"><w:pPr>\(old)</w:pPr></w:pPrChange></w:pPr>", TestXML.run("P2"))
            + TestXML.paragraph("0000P022", TestXML.run("P3")) + s2
        let out = try apply(body, FormPlan(truncateFrom: "0000P021"))
        XCTAssertEqual(TestXML.string(out), TestXML.string(TestXML.document(TestXML.paragraph("0000P020", TestXML.run("P1")) + s2)))
    }

    func testTruncateFindsASectionBreakInsideABodyLevelContentControl() throws {
        let wrapped = "<w:sdt><w:sdtPr/><w:sdtContent>"
            + TestXML.paragraph("0000P031", pPr: "<w:pPr>\(s1)</w:pPr>", TestXML.run("控制項內")) + "</w:sdtContent></w:sdt>"
        let body = TestXML.paragraph("0000P030", TestXML.run("P1")) + TestXML.paragraph("0000P032", TestXML.run("切點")) + wrapped + s2
        let out = try apply(body, FormPlan(truncateFrom: "0000P032"))
        XCTAssertEqual(TestXML.string(out), TestXML.string(TestXML.document(TestXML.paragraph("0000P030", TestXML.run("P1")) + s1)))
    }

    func testTruncateInsideATableIsRefused() {
        let body = TestXML.paragraph("0000P010", TestXML.run("前"))
            + TestXML.table([TestXML.cell(TestXML.paragraph("0000P011", TestXML.run("表內")))]) + s2
        XCTAssertThrowsError(try apply(body, FormPlan(truncateFrom: "0000P011"))) {
            XCTAssertEqual($0 as? FormError, .notBodyChild("0000P011"))
        }
    }

    func testTruncateAtTheFirstChildIsRefused() {
        XCTAssertThrowsError(try apply(sectionedBody, FormPlan(truncateFrom: "0000P001"))) {
            XCTAssertEqual($0 as? FormError, .firstBodyChild("0000P001"))
        }
    }
}
