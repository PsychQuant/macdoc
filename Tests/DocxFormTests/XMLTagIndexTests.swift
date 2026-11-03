// XMLTagIndexTests.swift — the tag scanner behind form normalization (#249).

import XCTest
@testable import DocxForm

final class XMLTagIndexTests: XCTestCase {
    func testGreaterThanInsideAttributeValueDoesNotEndTheTag() throws {
        let index = try XMLTagIndex(#"<a x="1>2" y='3'><b/></a>"#)
        XCTAssertEqual(index.tags.map(\.name), ["a", "b", "a"])
        XCTAssertEqual(index.tags.map(\.kind), [.open, .selfClosing, .close])
        XCTAssertEqual(index.attribute("x", of: 0), "1>2")
        XCTAssertEqual(index.attribute("y", of: 0), "3")
    }

    func testCommentAndCDATAAreSkipped() throws {
        let index = try XMLTagIndex("<a><!-- <w:p> --><![CDATA[<w:p>]]><?pi <w:p>?><b/></a>")
        XCTAssertEqual(index.elements(named: "w:p"), [])
        XCTAssertEqual(index.tags.map(\.name), ["a", "b", "a"])
    }

    func testNestedTableResolvesToTheInnerCell() throws {
        let inner = TestXML.table([TestXML.cell(TestXML.paragraph("00000002", TestXML.run("inner")))])
        let outer = TestXML.table([TestXML.cell(TestXML.paragraph("00000001", TestXML.run("outer")) + inner)])
        let index = try XMLTagIndex(TestXML.document(outer))
        let cells = index.elements(named: "w:tc")
        XCTAssertEqual(cells.count, 2)
        guard case .found(let innerParagraph) = FormLocator.paragraph(withId: "00000002", in: index),
              case .found(let outerParagraph) = FormLocator.paragraph(withId: "00000001", in: index) else {
            return XCTFail("paragraphs not found")
        }
        XCTAssertEqual(index.ancestor(of: innerParagraph, named: "w:tc"), cells[1])
        XCTAssertEqual(index.ancestor(of: outerParagraph, named: "w:tc"), cells[0])
    }

    func testPropertyChangeHoldsItsOwnParagraphProperties() throws {
        let xml = "<w:p><w:pPr><w:jc w:val=\"left\"/><w:pPrChange><w:pPr><w:numPr/></w:pPr></w:pPrChange></w:pPr></w:p>"
        let index = try XMLTagIndex(xml)
        let pPr = index.child(of: 0, named: "w:pPr")!
        XCTAssertEqual(index.children(of: pPr).map { index.tags[$0].name }, ["w:jc", "w:pPrChange"])
        XCTAssertNil(index.child(of: pPr, named: "w:numPr"))
    }

    func testMismatchedCloseIsRejected() {
        XCTAssertThrowsError(try XMLTagIndex("<a><b></a></b>"))
        XCTAssertThrowsError(try XMLTagIndex("<a>"))
        XCTAssertThrowsError(try XMLTagIndex("<a x=\"1>"))
    }

    func testDoctypeIsRefused() {
        XCTAssertThrowsError(try XMLTagIndex("<!DOCTYPE a [<!ENTITY x \">\">]><a/>")) {
            guard case .doctypeNotAllowed = $0 as? XMLScanError else { return XCTFail("\($0)") }
        }
    }

    func testTextTakesCDATALiterallyAndDropsComments() throws {
        let index = try XMLTagIndex("<w:t>a&amp;<![CDATA[<b>&amp;]]><!-- c -->d</w:t>")
        XCTAssertEqual(index.text(of: 0), "a&<b>&amp;d")
    }

    func testTextIsEntityDecoded() throws {
        let index = try XMLTagIndex("<w:t>a&amp;b&#x25A1;&#9632;&lt;</w:t>")
        XCTAssertEqual(index.text(of: 0), "a&b\u{25A1}\u{25A0}<")
    }
}
