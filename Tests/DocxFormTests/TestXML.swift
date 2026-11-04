// TestXML.swift — builders for synthetic word/document.xml fixtures.

import Foundation
@testable import DocxForm

enum TestXML {
    static let namespaces = [
        #"xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main""#,
        #"xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml""#,
        #"xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math""#,
        #"xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing""#,
    ].joined(separator: " ")

    static func document(_ body: String) -> [UInt8] {
        Array(("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<w:document \(namespaces)><w:body>\(body)</w:body></w:document>").utf8)
    }

    static func paragraph(_ id: String?, pPr: String = "", _ content: String = "") -> String {
        let attr = id.map { " w14:paraId=\"\($0)\"" } ?? ""
        return "<w:p\(attr)>\(pPr)\(content)</w:p>"
    }

    static func run(_ text: String, rPr: String = "") -> String {
        "<w:r>\(rPr)<w:t xml:space=\"preserve\">\(XMLText.escapeText(text))</w:t></w:r>"
    }

    static func cell(_ content: String, tcPr: String = "<w:tcPr><w:tcW w:w=\"2000\" w:type=\"dxa\"/></w:tcPr>") -> String {
        "<w:tc>\(tcPr)\(content)</w:tc>"
    }

    static func table(_ cells: [String]) -> String {
        "<w:tbl><w:tblPr/><w:tblGrid/><w:tr>\(cells.joined())</w:tr></w:tbl>"
    }

    static let bodySection = "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/></w:sectPr>"

    static func numbering(boxLevelText: String = "\u{25A1}") -> [UInt8] {
        Array(("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            + "<w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
            + "<w:abstractNum w:abstractNumId=\"7\"><w:lvl w:ilvl=\"0\"><w:lvlText w:val=\"\(boxLevelText)\"/></w:lvl></w:abstractNum>"
            + "<w:abstractNum w:abstractNumId=\"8\"><w:lvl w:ilvl=\"0\"><w:lvlText w:val=\"%1.\"/></w:lvl></w:abstractNum>"
            + "<w:num w:numId=\"3\"><w:abstractNumId w:val=\"7\"/></w:num>"
            + "<w:num w:numId=\"4\"><w:abstractNumId w:val=\"8\"/></w:num>"
            + "</w:numbering>").utf8)
    }

    static let numbered = "<w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"3\"/></w:numPr></w:pPr>"

    static func string(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }

    /// The paragraph element carrying `id`, as a string.
    static func paragraphXML(_ id: String, in bytes: [UInt8]) throws -> String {
        let index = try XMLTagIndex(bytes)
        guard case .found(let p) = FormLocator.paragraph(withId: id, in: index) else {
            throw NSError(domain: "TestXML", code: 1, userInfo: [NSLocalizedDescriptionKey: "no paragraph \(id)"])
        }
        return index.elementString(p)
    }

    /// Direct child element names of the first element named `name` inside `fragment`.
    static func childNames(of name: String, in fragment: String) throws -> [String] {
        let index = try XMLTagIndex(fragment)
        guard let e = index.elements(named: name).first else { return [] }
        return index.children(of: e).map { index.tags[$0].name }
    }

    /// Visible text of the paragraph carrying `id`.
    static func text(_ id: String, in bytes: [UInt8]) throws -> String {
        let index = try XMLTagIndex(bytes)
        guard case .found(let p) = FormLocator.paragraph(withId: id, in: index) else { return "" }
        return FormClassifier.ownText(of: p, in: index)
    }
}
