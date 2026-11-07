// Issue252LimitsTests.swift — lookup tables and resource limits for DocxForm
// (macdoc#252): paraId and element-name tables built once per index, scan
// limits on nesting depth and tag count, strict character references, and
// package limits on entry count and entry names.

import XCTest
import ZIPFoundation
@testable import DocxForm

final class Issue252LimitsTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("docxform-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func nested(_ depth: Int) -> String {
        String(repeating: "<a>", count: depth) + String(repeating: "</a>", count: depth)
    }

    // MARK: scan limits

    /// Foundation's XMLParser accepts 257 nested elements and rejects 258
    /// (measured); the scan refuses exactly what the output check would.
    func testScanAcceptsTheDeepestNestingXMLParserAccepts() throws {
        XCTAssertNoThrow(try XMLTagIndex(nested(XMLTagIndex.maxDepth)))
        XCTAssertEqual(XMLTagIndex.maxDepth, 257)
    }

    /// The limit is the output check's own: FormPlan.checkWellFormed (the
    /// XMLParser every apply result goes through) accepts the scan's deepest
    /// nesting and refuses one level more.
    func testOutputCheckParserAcceptsExactlyTheScanDepth() {
        XCTAssertNoThrow(try FormPlan.checkWellFormed(Array(nested(XMLTagIndex.maxDepth).utf8)))
        XCTAssertThrowsError(try FormPlan.checkWellFormed(Array(nested(XMLTagIndex.maxDepth + 1).utf8)))
    }

    func testScanRefusesNestingDeeperThanTheLimit() {
        let xml = nested(XMLTagIndex.maxDepth + 1)
        XCTAssertThrowsError(try XMLTagIndex(xml)) {
            guard case .tooDeep(let limit, _)? = $0 as? XMLScanError else { return XCTFail("\($0)") }
            XCTAssertEqual(limit, XMLTagIndex.maxDepth)
        }
    }

    func testSelfClosingTagCountsTowardDepth() {
        let xml = String(repeating: "<a>", count: 3) + "<b/>" + String(repeating: "</a>", count: 3)
        XCTAssertNoThrow(try XMLTagIndex(Array(xml.utf8), maxDepth: 4))
        XCTAssertThrowsError(try XMLTagIndex(Array(xml.utf8), maxDepth: 3)) {
            guard case .tooDeep(3, _)? = $0 as? XMLScanError else { return XCTFail("\($0)") }
        }
    }

    func testScanRefusesMoreTagsThanTheLimit() {
        let xml = "<a><b/><b/></a>"   // four tags: open, two self-closing, close
        XCTAssertNoThrow(try XMLTagIndex(Array(xml.utf8), maxTags: 4))
        XCTAssertThrowsError(try XMLTagIndex(Array(xml.utf8), maxTags: 3)) {
            XCTAssertEqual($0 as? XMLScanError, .tooManyTags(limit: 3))
        }
    }

    func testScanLimitMessagesNameTheLimit() {
        XCTAssertTrue(XMLScanError.tooDeep(limit: 257, at: 12).description.contains("257"))
        XCTAssertTrue(XMLScanError.tooManyTags(limit: 5_000_000).description.contains("5000000"))
    }

    // MARK: lookup tables

    /// The previous lookup, kept here as the reference the table must match.
    private func referenceLookup(_ id: String, in index: XMLTagIndex) -> FormLocator.Lookup {
        var paragraphs: [Int] = []
        var otherCarrier: String?
        for (i, tag) in index.tags.enumerated() where tag.kind != .close && !tag.attributes.isEmpty {
            guard index.attribute("w14:paraId", of: i) == id else { continue }
            if tag.name == "w:p" { paragraphs.append(i) } else if otherCarrier == nil { otherCarrier = tag.name }
        }
        switch paragraphs.count {
        case 1: return .found(paragraphs[0])
        case 0: return otherCarrier.map { .notOnParagraph(carrier: $0) } ?? .notFound
        default: return .ambiguous(count: paragraphs.count)
        }
    }

    func testParaIdTableMatchesTheFullScan() throws {
        let body = TestXML.paragraph("0000AAAA", TestXML.run("一"))
            + TestXML.paragraph("0000BBBB", TestXML.run("二")) + TestXML.paragraph("0000BBBB", TestXML.run("三"))
            + "<w:tbl><w:tr w14:paraId=\"0000CCCC\"><w:tc>" + TestXML.paragraph("0000DDDD", TestXML.run("四"))
            + "</w:tc></w:tr></w:tbl>"
            + "<w:p w14:paraId='0000EEEE' w:rsidR=\"w14:paraId=&quot;0000FFFF&quot;\">" + TestXML.run("五") + "</w:p>"
            + "<w:p w14:paraId=\"0000&#x41;AAA\">" + TestXML.run("六") + "</w:p>"
            + TestXML.bodySection
        let index = try XMLTagIndex(TestXML.document(body))
        for id in ["0000AAAA", "0000BBBB", "0000CCCC", "0000DDDD", "0000EEEE", "0000FFFF", "0000AAAA0", "0000AAAA",
                   "0000AAAA".lowercased(), "0000AAAA" + "", "DEADBEEF"] {
            XCTAssertEqual(FormLocator.paragraph(withId: id, in: index), referenceLookup(id, in: index), id)
        }
    }

    func testElementsNamedMatchesAFullFilterInDocumentOrder() throws {
        let body = TestXML.paragraph("0000AAAA", TestXML.run("一") + "<w:bookmarkStart w:id=\"1\"/>")
            + "<w:tbl><w:tr><w:tc>" + TestXML.paragraph("0000BBBB", TestXML.run("二")) + "</w:tc></w:tr></w:tbl>"
            + TestXML.paragraph("0000CCCC", "<w:bookmarkEnd w:id=\"1\"/>") + TestXML.bodySection
        let index = try XMLTagIndex(TestXML.document(body))
        for name in ["w:p", "w:r", "w:bookmarkStart", "w:bookmarkEnd", "w:tbl", "w:nothing"] {
            let full = index.tags.indices.filter { index.tags[$0].kind != .close && index.tags[$0].name == name }
            XCTAssertEqual(index.elements(named: name), full, name)
        }
    }

    /// The merged lookup the deletion checks walk (keptMarkers, fieldSplit,
    /// commentOrphan) equals a full filter, in document order, once per
    /// element even when a name is given twice.
    func testElementsNamedAnyOfMatchesAFullFilterInDocumentOrder() throws {
        let body = TestXML.paragraph("0000AAAA", "<w:bookmarkStart w:id=\"1\"/>" + TestXML.run("一")
                                     + "<w:commentRangeStart w:id=\"0\"/>")
            + TestXML.paragraph("0000BBBB", "<w:bookmarkEnd w:id=\"1\"/>" + "<w:commentRangeEnd w:id=\"0\"/>"
                                + "<w:r><w:commentReference w:id=\"0\"/></w:r>")
            + TestXML.bodySection
        let index = try XMLTagIndex(TestXML.document(body))
        let sets: [[String]] = [["w:bookmarkStart", "w:bookmarkEnd"],
                                ["w:commentRangeStart", "w:commentRangeEnd", "w:commentReference"],
                                ["w:p", "w:r", "w:nothing"], ["w:bookmarkEnd", "w:bookmarkStart", "w:bookmarkEnd"], []]
        for names in sets {
            let wanted = Set(names)
            let full = index.tags.indices.filter { index.tags[$0].kind != .close && wanted.contains(index.tags[$0].name) }
            XCTAssertEqual(index.elements(namedAnyOf: names), full, "\(names)")
        }
    }

    // MARK: character references

    func testDecodeAcceptsWellFormedReferences() {
        XCTAssertEqual(XMLText.decode("&#65;&#x42;&#x43;&amp;"), "ABC&")
        XCTAssertEqual(XMLText.decode("&#x4a;&#x4A;"), "JJ")   // hex digits in either case
        XCTAssertEqual(XMLText.decode("&#x1F600;"), "\u{1F600}")
        XCTAssertEqual(XMLText.decode("&#9;&#xA;&#13;"), "\t\n\r")
    }

    /// An uppercase `X` (XML 1.0 CharRef has only `&#x`), a sign, an empty
    /// number, a stray character or a value outside the XML 1.0 Char
    /// production is not a reference; it is kept as written.
    func testDecodeKeepsMalformedReferencesAsWritten() {
        for literal in ["&#X43;", "&#+65;", "&#-65;", "&#;", "&#x;", "&#x+41;", "&#6 5;", "&#65a;", "&#xG1;",
                        "&#1;", "&#x0;", "&#xB;", "&#x1F;", "&#xD800;", "&#xFFFE;", "&#xFFFF;", "&#x110000;",
                        "&#99999999999;"] {
            XCTAssertEqual(XMLText.decode(literal), literal, literal)
        }
    }

    /// Decoding walks Unicode scalars, as an XML parser does: a combining
    /// mark after `;` or `&` must not hide the delimiter (#252 verify R1).
    func testDecodeWalksScalarsNotCharacters() {
        XCTAssertEqual(Array(XMLText.decode("&#65;\u{301}").unicodeScalars), ["A", "\u{301}"])
        XCTAssertEqual(Array(XMLText.decode("&amp;\u{301}x").unicodeScalars), ["&", "\u{301}", "x"])
        // `&` followed by a combining mark starts no reference; it stays as written.
        XCTAssertEqual(Array(XMLText.decode("&\u{301}#65;").unicodeScalars), Array("&\u{301}#65;".unicodeScalars))
    }

    /// A reference after a long run of text, and a reference with a long run
    /// of leading zeros (XML allows them), decode like short ones (#252 verify R2).
    func testDecodeHandlesLongTextAndLongDigitRuns() {
        let text = String(repeating: "a", count: 200_000)
        XCTAssertEqual(XMLText.decode(text + "&amp;" + text), text + "&" + text)
        XCTAssertEqual(XMLText.decode("&#" + String(repeating: "0", count: 100_000) + "65;"), "A")
        XCTAssertEqual(XMLText.decode("&#x" + String(repeating: "0", count: 100_000) + "41;"), "A")
        XCTAssertEqual(XMLText.decode("&#4294967296;"), "&#4294967296;")   // past UInt32
        XCTAssertEqual(XMLText.decode("x&" + text), "x&" + text)            // no `;` after `&`
    }

    // MARK: package limits

    private func package(at url: URL, extra: [DocxPackage.Entry] = []) throws {
        try DocxPackage.write([
            DocxPackage.Entry(path: "[Content_Types].xml", data: Data("<Types/>".utf8)),
            DocxPackage.Entry(path: "word/document.xml", data: Data(TestXML.document(TestXML.paragraph("0000A001", TestXML.run("一"))))),
            DocxPackage.Entry(path: "word/numbering.xml", data: Data("<w:numbering xmlns:w=\"x\"/>".utf8)),
        ] + extra, to: url)
    }

    func testPackageWithMoreEntriesThanTheLimitIsRefused() throws {
        let url = try tempDir().appendingPathComponent("in.docx")
        try package(at: url, extra: [DocxPackage.Entry(path: "a.xml", data: Data("<a/>".utf8))])
        XCTAssertNoThrow(try DocxPackage.read(from: url, maxEntries: 4))
        XCTAssertThrowsError(try DocxPackage.read(from: url, maxEntries: 3)) {
            XCTAssertEqual($0 as? DocxPackageError, .tooManyEntries(limit: 3))
        }
        XCTAssertEqual(DocxPackage.maxEntries, 10_000)
    }

    /// Closed list: a name starting with `/` or `\`, a name starting with an
    /// ASCII letter and `:`, or one with a `..` segment between `/` or `\`
    /// separators, all read as Unicode scalars. Nothing else is refused on
    /// its name.
    func testSuspiciousEntryNamesAreRefused() throws {
        for name in ["/etc/x.xml", "\\x.xml", "../x.xml", "word/../../x.xml", "word\\..\\x.xml", "word/..",
                     // A combining mark after the separator joins it into one Character;
                     // the bytes an extractor reads still hold the separator (#252 verify R1).
                     "/\u{301}etc/x.xml", "\\\u{301}x.xml", "../\u{301}x.xml", "word/../\u{301}x.xml",
                     // A Windows drive is an absolute path too.
                     "C:\\x.xml", "c:x.xml", "C:..\\x.xml", "Z:/x.xml"] {
            let url = try tempDir().appendingPathComponent("in.docx")
            try package(at: url, extra: [DocxPackage.Entry(path: name, data: Data("<a/>".utf8))])
            XCTAssertThrowsError(try DocxPackage.read(from: url), name) {
                XCTAssertEqual($0 as? DocxPackageError, .suspiciousEntryName(name), name)
            }
            XCTAssertThrowsError(try DocxPackage.readParts(from: url, paths: [DocxPackage.documentPart]), name)
        }
        for name in ["word/..x.xml", "word/x..xml", "word/.x.xml", "a..b/c.xml",
                     "word/C:x.xml", "1:x.xml", "\u{E9}:x.xml", "word/.\u{301}./x.xml"] {
            let url = try tempDir().appendingPathComponent("in.docx")
            try package(at: url, extra: [DocxPackage.Entry(path: name, data: Data("<a/>".utf8))])
            XCTAssertNoThrow(try DocxPackage.read(from: url), name)
        }
    }

    func testReadPartsExtractsOnlyTheNamedParts() throws {
        let url = try tempDir().appendingPathComponent("in.docx")
        let big = Data(repeating: 0x41, count: 64 * 1024)
        try package(at: url, extra: [DocxPackage.Entry(path: "word/media/big.bin", data: big)])
        // The size limit counts only what is extracted: the big entry is skipped.
        let parts = try DocxPackage.readParts(from: url, paths: [DocxPackage.documentPart, DocxPackage.numberingPart],
                                              limit: 16 * 1024)
        XCTAssertEqual(parts.map(\.path), [DocxPackage.documentPart, DocxPackage.numberingPart])
        XCTAssertThrowsError(try DocxPackage.read(from: url, limit: 16 * 1024)) {
            XCTAssertEqual($0 as? DocxPackageError, .tooLarge(limit: 16 * 1024))
        }
        // The entry-count limit still covers the whole archive.
        XCTAssertThrowsError(try DocxPackage.readParts(from: url, paths: [DocxPackage.documentPart], maxEntries: 3)) {
            XCTAssertEqual($0 as? DocxPackageError, .tooManyEntries(limit: 3))
        }
        // A part that is not there is simply absent.
        XCTAssertEqual(try DocxPackage.readParts(from: url, paths: ["word/missing.xml"]).count, 0)
    }

    func testPackageLimitMessagesNameTheLimitAndTheEntry() {
        XCTAssertTrue(DocxPackageError.tooManyEntries(limit: 10_000).description.contains("10000"))
        XCTAssertTrue(DocxPackageError.suspiciousEntryName("../x.xml").description.contains("../x.xml"))
    }
}
