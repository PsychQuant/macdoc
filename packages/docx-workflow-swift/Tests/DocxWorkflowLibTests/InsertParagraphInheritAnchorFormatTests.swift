// InsertParagraphInheritAnchorFormatTests — PsychQuant/macdoc#251.
//
// End to end through Manifest → CertifiedTransaction on a document shaped
// like an official form: the anchor paragraph carries its own formatting in
// <w:pPr> (style, page break before, list numbering, spacing, indentation, a
// tracked insertion on its paragraph mark, a section break) and its run
// carries fonts and size. Before ooxml-swift 3.20.0 an inserted paragraph
// fell back to the document defaults on such a form.
//
// The copy rules themselves belong to ooxml-swift (its
// InsertParagraphAnchorFormatTests covers each one). These tests pin what
// this library adds: the manifest field reaches the reducer in both
// directions, leaving it out keeps the old output, and the certified
// transaction still changes only word/document.xml.

import XCTest
import DocxWorkflowLib

final class InsertParagraphInheritAnchorFormatTests: XCTestCase {

    private static let wordNamespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

    /// The anchor ("Name:") ends section 1 with its own section break; the
    /// paragraph after it ("Signature") sits in the last section.
    private static let formDocumentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="\(wordNamespace)"><w:body>\
        <w:p><w:pPr><w:pStyle w:val="FormField"/><w:pageBreakBefore/>\
        <w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>\
        <w:spacing w:before="120" w:after="240"/><w:ind w:left="720"/>\
        <w:rPr><w:ins w:id="5" w:author="Reviewer" w:date="2026-01-01T00:00:00Z"/><w:b/></w:rPr>\
        <w:sectPr><w:pgSz w:w="11906" w:h="16838"/></w:sectPr></w:pPr>\
        <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:eastAsia="DFKai-SB"/><w:sz w:val="28"/></w:rPr>\
        <w:t>Name:</w:t></w:r></w:p>\
        <w:p><w:r><w:t>Signature</w:t></w:r></w:p>\
        <w:sectPr><w:pgSz w:w="11906" w:h="16838"/></w:sectPr>\
        </w:body></w:document>
        """

    private static let anchorPPrChildren = ["pStyle", "pageBreakBefore", "numPr", "spacing", "ind", "rPr", "sectPr"]

    // MARK: - Fixtures

    private func makeTempURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).docx")
    }

    /// A writer-produced package whose word/document.xml is replaced by the
    /// form above, so every other part is whatever DocxWriter emits.
    private func makeFormBaseline() throws -> URL {
        var doc = WordDocument()
        doc.appendParagraph(Paragraph(text: "placeholder"))
        let plain = makeTempURL(prefix: "inherit-plain")
        try DocxWriter.writeData(doc).write(to: plain)
        defer { try? FileManager.default.removeItem(at: plain) }

        let dir = try ZipHelper.unzip(plain)
        defer { ZipHelper.cleanup(dir) }
        try Data(Self.formDocumentXML.utf8).write(to: dir.appendingPathComponent("word/document.xml"))
        let url = makeTempURL(prefix: "inherit-baseline")
        try ZipHelper.zip(dir, to: url)
        return url
    }

    private func partBytes(of docx: URL) throws -> [String: Data] {
        let dir = try ZipHelper.unzip(docx)
        defer { ZipHelper.cleanup(dir) }
        var parts: [String: Data] = [:]
        let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey])
        while let file = files?.nextObject() as? URL {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let name = file.standardizedFileURL.path
                .replacingOccurrences(of: dir.standardizedFileURL.path + "/", with: "")
            parts[name] = try Data(contentsOf: file)
        }
        return parts
    }

    /// Runs one insert_paragraph step through the certified transaction and
    /// returns the output's top-level body paragraphs, keyed by their text.
    private func apply(
        anchor: Anchor, inherit: Bool?, file: StaticString = #filePath, line: UInt = #line
    ) throws -> (paragraphs: [(text: String, element: XMLElement)], baseline: URL, output: URL) {
        let baseline = try makeFormBaseline()
        let output = makeTempURL(prefix: "inherit-out")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: output)
        }
        let manifest = Manifest(
            baseline: baseline.path,
            output: output.path,
            steps: [.insertParagraph(InsertParagraphStep(
                anchor: anchor, content: "Inserted entry", inheritAnchorFormat: inherit))]
        )
        let certificate: CertificationCertificate
        do {
            certificate = try CertifiedTransaction().apply(
                manifest: manifest, baselineURL: baseline, outputURL: output)
        } catch {
            XCTFail("CertifiedTransaction().apply threw: \(error)", file: file, line: line)
            throw error
        }
        XCTAssertEqual(certificate.status, .layer1Verified, file: file, line: line)
        XCTAssertEqual(certificate.changedParts, ["word/document.xml"], file: file, line: line)

        let before = try partBytes(of: baseline)
        let after = try partBytes(of: output)
        XCTAssertEqual(Set(after.keys), Set(before.keys), "parts were added or dropped", file: file, line: line)
        for (name, bytes) in before where name != "word/document.xml" {
            XCTAssertEqual(after[name], bytes, "\(name) changed although insert_paragraph only edits word/document.xml",
                           file: file, line: line)
        }

        let xml = try XMLDocument(data: XCTUnwrap(after["word/document.xml"]), options: [])
        let nodes = try xml.nodes(forXPath: "/*[local-name()='document']/*[local-name()='body']/*[local-name()='p']")
        let paragraphs = nodes.compactMap { $0 as? XMLElement }.map { (text: text(of: $0), element: $0) }
        return (paragraphs, baseline, output)
    }

    private func text(of paragraph: XMLElement) -> String {
        ((try? paragraph.nodes(forXPath: ".//*[local-name()='t']")) ?? []).compactMap(\.stringValue).joined()
    }

    private func child(_ element: XMLElement?, _ localName: String) -> XMLElement? {
        element?.children?.compactMap { $0 as? XMLElement }.first { $0.localName == localName }
    }

    private func childNames(_ element: XMLElement?) -> [String] {
        element?.children?.compactMap { ($0 as? XMLElement)?.localName } ?? []
    }

    private func paragraph(_ text: String, in list: [(text: String, element: XMLElement)]) throws -> XMLElement {
        try XCTUnwrap(list.first { $0.text == text }?.element, "no body paragraph with text \(text)")
    }

    private func firstRun(_ paragraph: XMLElement) -> XMLElement? { child(paragraph, "r") }

    // MARK: - after_text: format copied, section break moved to the new paragraph

    func testInsertAfterAnchorInheritsItsFormatAndTakesOverTheSectionBreak() throws {
        let result = try apply(anchor: .afterText("Name:"), inherit: true)
        XCTAssertEqual(result.paragraphs.map(\.text), ["Name:", "Inserted entry", "Signature"])

        let inserted = try paragraph("Inserted entry", in: result.paragraphs)
        let pPr = child(inserted, "pPr")
        XCTAssertEqual(childNames(pPr), ["pStyle", "spacing", "ind", "rPr", "sectPr"],
                       "list numbering and page break before are not copied; the section break moves here")
        XCTAssertEqual(child(pPr, "pStyle")?.attribute(forLocalName: "val", uri: Self.wordNamespace)?.stringValue,
                       "FormField")
        XCTAssertEqual(childNames(child(pPr, "rPr")), ["b"], "the paragraph mark's tracked insertion is not copied")
        XCTAssertNotNil(child(child(pPr, "sectPr"), "pgSz"))

        let runPr = child(firstRun(inserted), "rPr")
        XCTAssertEqual(childNames(runPr), ["rFonts", "sz"], "the new run takes the anchor run's text format")
        XCTAssertEqual(child(runPr, "rFonts")?.attribute(forLocalName: "eastAsia", uri: Self.wordNamespace)?.stringValue,
                       "DFKai-SB")
        XCTAssertEqual(child(runPr, "sz")?.attribute(forLocalName: "val", uri: Self.wordNamespace)?.stringValue, "28")

        let anchor = try paragraph("Name:", in: result.paragraphs)
        XCTAssertEqual(childNames(child(anchor, "pPr")), ["pStyle", "pageBreakBefore", "numPr", "spacing", "ind", "rPr"],
                       "the anchor keeps everything except the section break, which now ends section 1 one paragraph later")
    }

    // MARK: - before_text: format copied, section break stays on the anchor

    func testInsertBeforeAnchorInheritsItsFormatAndLeavesTheSectionBreak() throws {
        let result = try apply(anchor: .beforeText("Name:"), inherit: true)
        XCTAssertEqual(result.paragraphs.map(\.text), ["Inserted entry", "Name:", "Signature"])

        let inserted = try paragraph("Inserted entry", in: result.paragraphs)
        XCTAssertEqual(childNames(child(inserted, "pPr")), ["pStyle", "spacing", "ind", "rPr"],
                       "inserted before the anchor, the new paragraph is already in the anchor's section")
        XCTAssertEqual(childNames(child(firstRun(inserted), "rPr")), ["rFonts", "sz"])

        let anchor = try paragraph("Name:", in: result.paragraphs)
        XCTAssertEqual(childNames(child(anchor, "pPr")), Self.anchorPPrChildren, "the anchor is untouched")
    }

    // MARK: - field absent: the output is what it was before #251

    func testWithoutTheFieldTheInsertedParagraphStaysUnformatted() throws {
        let result = try apply(anchor: .afterText("Name:"), inherit: nil)
        XCTAssertEqual(result.paragraphs.map(\.text), ["Name:", "Inserted entry", "Signature"])

        let inserted = try paragraph("Inserted entry", in: result.paragraphs)
        XCTAssertNil(child(inserted, "pPr"), "no field, no copied paragraph format")
        XCTAssertNil(child(firstRun(inserted), "rPr"), "no field, no copied text format")

        let anchor = try paragraph("Name:", in: result.paragraphs)
        XCTAssertEqual(childNames(child(anchor, "pPr")), Self.anchorPPrChildren, "the anchor keeps its section break")
    }

    func testFalseBehavesLikeAbsent() throws {
        let result = try apply(anchor: .afterText("Name:"), inherit: false)
        let inserted = try paragraph("Inserted entry", in: result.paragraphs)
        XCTAssertNil(child(inserted, "pPr"))
        XCTAssertNil(child(firstRun(inserted), "rPr"))
        XCTAssertEqual(childNames(child(try paragraph("Name:", in: result.paragraphs), "pPr")), Self.anchorPPrChildren)
    }
}
