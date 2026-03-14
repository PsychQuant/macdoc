import Foundation
import CommonConverterSwift
import OOXMLSwift
import SwiftSoup

public struct HTMLToWordConverter: DocumentConverter {
    public static let sourceFormat = "html"

    public init() {}

    public func convert<W: StreamingOutput>(
        input: URL,
        output: inout W,
        options: ConversionOptions
    ) throws {
        let document = try convertToDocument(input: input, options: options)
        let documentXML = try renderDocumentXML(from: document)
        try output.write(documentXML)
    }

    public func convertToFile(
        input: URL,
        output: URL,
        options: ConversionOptions = .default
    ) throws {
        let document = try convertToDocument(input: input, options: options)
        try DocxWriter.write(document, to: output)
    }

    public func convertToDocument(
        input: URL,
        options: ConversionOptions = .default
    ) throws -> WordDocument {
        guard FileManager.default.fileExists(atPath: input.path) else {
            throw ConversionError.fileNotFound(input.path)
        }

        let html = try loadHTML(from: input)
        return try convertHTML(html, sourceURL: input, options: options)
    }

    public func convertHTML(
        _ html: String,
        sourceURL: URL? = nil,
        options: ConversionOptions = .default
    ) throws -> WordDocument {
        let parsed = try SwiftSoup.parse(html, sourceURL?.absoluteString ?? "")
        var builder = HTMLWordBuilder(parsed: parsed, sourceURL: sourceURL, options: options)
        return try builder.build()
    }

    private func loadHTML(from input: URL) throws -> String {
        if let utf8 = try? String(contentsOf: input, encoding: .utf8) {
            return utf8
        }
        if let latin1 = try? String(contentsOf: input, encoding: .isoLatin1) {
            return latin1
        }
        return try String(contentsOf: input, encoding: .utf8)
    }

    private func renderDocumentXML(from document: WordDocument) throws -> String {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("html-to-word-swift")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let archiveURL = tempRoot.appendingPathComponent("document.docx")
        try DocxWriter.write(document, to: archiveURL)

        let extracted = try ZipHelper.unzip(archiveURL)
        defer { ZipHelper.cleanup(extracted) }

        return try String(
            contentsOf: extracted.appendingPathComponent("word/document.xml"),
            encoding: .utf8
        )
    }
}

private struct HTMLWordBuilder {
    private var document = WordDocument()
    private let parsed: SwiftSoup.Document
    private let sourceURL: URL?
    private let options: ConversionOptions

    init(parsed: SwiftSoup.Document, sourceURL: URL?, options: ConversionOptions) {
        self.parsed = parsed
        self.sourceURL = sourceURL
        self.options = options
    }

    mutating func build() throws -> WordDocument {
        document.properties.title = try resolvedTitle()
        if let author = try resolvedAuthor(), !author.isEmpty {
            document.properties.creator = author
        }
        document.properties.subject = sourceURL?.lastPathComponent ?? "html"

        let nodes: [Node]
        if let body = parsed.body() {
            nodes = body.getChildNodes()
        } else {
            nodes = parsed.getChildNodes()
        }

        try emitBlockNodes(nodes)

        if document.body.children.isEmpty {
            document.appendParagraph(Paragraph())
        }

        return document
    }

    private mutating func emitBlockNodes(
        _ nodes: [Node],
        baseProperties: ParagraphProperties? = nil
    ) throws {
        for node in nodes {
            try emitBlock(node, baseProperties: baseProperties)
        }
    }

    private mutating func emitBlock(
        _ node: Node,
        baseProperties: ParagraphProperties? = nil
    ) throws {
        if let textNode = node as? TextNode {
            let text = normalizeInlineText(textNode.getWholeText(), preserveWhitespace: false)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            var paragraph = Paragraph(text: text)
            if let baseProperties {
                paragraph.properties = baseProperties
            }
            document.appendParagraph(paragraph)
            return
        }

        guard let element = node as? Element else { return }
        let tag = element.tagName().lowercased()
        if ignoredTags.contains(tag) {
            return
        }

        switch tag {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            guard var paragraph = try makeParagraph(from: element.getChildNodes(), baseProperties: baseProperties) else {
                return
            }
            paragraph.properties.style = headingStyle(for: tag)
            document.appendParagraph(paragraph)

        case "p":
            if let paragraph = try makeParagraph(from: element.getChildNodes(), baseProperties: baseProperties) {
                document.appendParagraph(paragraph)
            }

        case "ul", "ol":
            try emitList(element, context: nil)

        case "blockquote":
            var quoteProperties = baseProperties ?? ParagraphProperties()
            quoteProperties.indentation = Indentation(left: 720)
            if containsBlockChildren(element) {
                try emitBlockNodes(element.getChildNodes(), baseProperties: quoteProperties)
            } else if let paragraph = try makeParagraph(from: element.getChildNodes(), baseProperties: quoteProperties) {
                document.appendParagraph(paragraph)
            }

        case "pre":
            if let paragraph = try makePreformattedParagraph(from: element, baseProperties: baseProperties) {
                document.appendParagraph(paragraph)
            }

        case "table":
            try emitTable(element)

        case "hr":
            let line = String(repeating: "—", count: 12)
            var paragraph = Paragraph(text: line)
            if let baseProperties {
                paragraph.properties = baseProperties
            }
            document.appendParagraph(paragraph)

        default:
            if containerTags.contains(tag) {
                if containsBlockChildren(element) {
                    try emitBlockNodes(element.getChildNodes(), baseProperties: baseProperties)
                } else if let paragraph = try makeParagraph(from: element.getChildNodes(), baseProperties: baseProperties) {
                    document.appendParagraph(paragraph)
                }
            } else if let paragraph = try makeParagraph(from: [element], baseProperties: baseProperties) {
                document.appendParagraph(paragraph)
            }
        }
    }

    private mutating func emitList(_ list: Element, context: ListContext?) throws {
        let kind = list.tagName().lowercased() == "ol" ? ListKind.ordered : .unordered
        let level = context.map { $0.level + 1 } ?? 0

        let numId: Int
        if let context, context.kind == kind {
            numId = context.numId
        } else {
            numId = kind == .ordered
                ? document.numbering.createNumberedList()
                : document.numbering.createBulletList()
        }

        let currentContext = ListContext(kind: kind, numId: numId, level: level)
        let items = list.children().array().filter { $0.tagName().lowercased() == "li" }

        for item in items {
            let contentNodes = item.getChildNodes().filter { node in
                guard let child = node as? Element else { return true }
                let tag = child.tagName().lowercased()
                return tag != "ul" && tag != "ol"
            }

            if var paragraph = try makeParagraph(from: contentNodes) {
                paragraph.properties.numbering = NumberingInfo(numId: currentContext.numId, level: currentContext.level)
                document.appendParagraph(paragraph)
            }

            let nestedLists = item.children().array().filter {
                let tag = $0.tagName().lowercased()
                return tag == "ul" || tag == "ol"
            }
            for nested in nestedLists {
                try emitList(nested, context: currentContext)
            }
        }
    }

    private mutating func emitTable(_ table: Element) throws {
        let rows = try table.select("tr").array()
        guard !rows.isEmpty else { return }

        let wordRows: [TableRow] = try rows.map { row in
            let cells = row.children().array().filter {
                let tag = $0.tagName().lowercased()
                return tag == "th" || tag == "td"
            }

            let wordCells: [TableCell] = try cells.map { cell in
                if let paragraph = try makeParagraph(from: cell.getChildNodes()) {
                    return TableCell(paragraphs: [paragraph])
                }
                return TableCell()
            }

            var tableRow = TableRow(cells: wordCells)
            tableRow.properties.isHeader = cells.contains { $0.tagName().lowercased() == "th" }
            return tableRow
        }

        var wordTable = Table(rows: wordRows)
        wordTable.properties.borders = .all(Border())
        document.appendTable(wordTable)
    }

    private mutating func makePreformattedParagraph(
        from element: Element,
        baseProperties: ParagraphProperties?
    ) throws -> Paragraph? {
        let rawText = try plainText(from: element.getChildNodes(), preserveWhitespace: true)
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .newlines)

        guard !normalized.isEmpty else { return nil }

        var paragraph = Paragraph()
        if let baseProperties {
            paragraph.properties = baseProperties
        }

        let lines = normalized.components(separatedBy: .newlines)
        var codeProperties = RunProperties()
        codeProperties.fontName = "Menlo"

        for (index, line) in lines.enumerated() {
            appendTextRun(line, properties: codeProperties, to: &paragraph)
            if index < lines.count - 1 {
                paragraph.runs.append(rawXMLRun("<w:r><w:br/></w:r>"))
            }
        }

        finalizeParagraph(&paragraph)
        return paragraph.runs.isEmpty ? nil : paragraph
    }

    private mutating func makeParagraph(
        from nodes: [Node],
        baseProperties: ParagraphProperties? = nil
    ) throws -> Paragraph? {
        var paragraph = Paragraph()
        if let baseProperties {
            paragraph.properties = baseProperties
        }

        try appendInline(nodes, to: &paragraph, properties: RunProperties(), preserveWhitespace: false)
        finalizeParagraph(&paragraph)

        return paragraph.runs.isEmpty ? nil : paragraph
    }

    private mutating func appendInline(
        _ nodes: [Node],
        to paragraph: inout Paragraph,
        properties: RunProperties,
        preserveWhitespace: Bool
    ) throws {
        for node in nodes {
            try appendInline(node, to: &paragraph, properties: properties, preserveWhitespace: preserveWhitespace)
        }
    }

    private mutating func appendInline(
        _ node: Node,
        to paragraph: inout Paragraph,
        properties: RunProperties,
        preserveWhitespace: Bool
    ) throws {
        if let textNode = node as? TextNode {
            let text = normalizeInlineText(textNode.getWholeText(), preserveWhitespace: preserveWhitespace)
            appendTextRun(text, properties: properties, to: &paragraph)
            return
        }

        guard let element = node as? Element else { return }
        let tag = element.tagName().lowercased()

        switch tag {
        case "strong", "b":
            var next = properties
            next.bold = true
            try appendInline(element.getChildNodes(), to: &paragraph, properties: next, preserveWhitespace: preserveWhitespace)

        case "em", "i":
            var next = properties
            next.italic = true
            try appendInline(element.getChildNodes(), to: &paragraph, properties: next, preserveWhitespace: preserveWhitespace)

        case "u":
            var next = properties
            next.underline = .single
            try appendInline(element.getChildNodes(), to: &paragraph, properties: next, preserveWhitespace: preserveWhitespace)

        case "del", "s", "strike":
            var next = properties
            next.strikethrough = true
            try appendInline(element.getChildNodes(), to: &paragraph, properties: next, preserveWhitespace: preserveWhitespace)

        case "sup":
            var next = properties
            next.verticalAlign = .superscript
            try appendInline(element.getChildNodes(), to: &paragraph, properties: next, preserveWhitespace: true)

        case "sub":
            var next = properties
            next.verticalAlign = .subscript
            try appendInline(element.getChildNodes(), to: &paragraph, properties: next, preserveWhitespace: true)

        case "mark":
            var next = properties
            next.highlight = .yellow
            try appendInline(element.getChildNodes(), to: &paragraph, properties: next, preserveWhitespace: preserveWhitespace)

        case "code":
            var next = properties
            next.fontName = "Menlo"
            try appendInline(element.getChildNodes(), to: &paragraph, properties: next, preserveWhitespace: true)

        case "br":
            paragraph.runs.append(rawXMLRun("<w:r><w:br/></w:r>"))

        case "a":
            let href = (try? element.attr("href"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let displayText = try plainText(from: element.getChildNodes(), preserveWhitespace: false)
            guard !displayText.isEmpty else { return }
            if href.isEmpty {
                appendTextRun(displayText, properties: properties, to: &paragraph)
            } else {
                paragraph.runs.append(makeHyperlinkRun(text: displayText, href: href))
            }

        case "img":
            let alt = (try? element.attr("alt"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let fallback = (try? element.attr("src"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "image"
            let label = alt.isEmpty ? "[Image: \(fallback)]" : "[Image: \(alt)]"
            appendTextRun(label, properties: properties, to: &paragraph)

        default:
            try appendInline(element.getChildNodes(), to: &paragraph, properties: properties, preserveWhitespace: preserveWhitespace)
        }
    }

    private mutating func makeHyperlinkRun(text: String, href: String) -> Run {
        let escapedText = escapeXML(text)

        if href.hasPrefix("#") {
            let anchor = escapeXML(String(href.dropFirst()))
            return rawXMLRun(
                "<w:hyperlink w:anchor=\"\(anchor)\"><w:r><w:rPr><w:rStyle w:val=\"Hyperlink\"/><w:color w:val=\"0563C1\"/><w:u w:val=\"single\"/></w:rPr><w:t xml:space=\"preserve\">\(escapedText)</w:t></w:r></w:hyperlink>"
            )
        }

        let relationshipId = "rIdHTMLLink\(document.hyperlinkReferences.count + 1)"
        document.hyperlinkReferences.append(
            HyperlinkReference(relationshipId: relationshipId, url: href)
        )

        return rawXMLRun(
            "<w:hyperlink r:id=\"\(relationshipId)\"><w:r><w:rPr><w:rStyle w:val=\"Hyperlink\"/><w:color w:val=\"0563C1\"/><w:u w:val=\"single\"/></w:rPr><w:t xml:space=\"preserve\">\(escapedText)</w:t></w:r></w:hyperlink>"
        )
    }

    private func plainText(from nodes: [Node], preserveWhitespace: Bool) throws -> String {
        var result = ""
        for node in nodes {
            if let textNode = node as? TextNode {
                result += normalizeInlineText(textNode.getWholeText(), preserveWhitespace: preserveWhitespace)
                continue
            }
            guard let element = node as? Element else { continue }
            let tag = element.tagName().lowercased()
            if tag == "br" {
                result += preserveWhitespace ? "\n" : " "
                continue
            }
            if tag == "img" {
                let alt = (try? element.attr("alt"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !alt.isEmpty {
                    result += alt
                }
                continue
            }
            result += try plainText(from: element.getChildNodes(), preserveWhitespace: preserveWhitespace)
        }
        return preserveWhitespace ? result : collapseSpaces(result)
    }

    private func resolvedTitle() throws -> String {
        let title = try parsed.title().trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }
        if let sourceURL {
            return sourceURL.deletingPathExtension().lastPathComponent
        }
        return "HTML Document"
    }

    private func resolvedAuthor() throws -> String? {
        if let content = try parsed
            .select("meta[name=author], meta[name=Author]")
            .first()?
            .attr("content")
            .trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
            return content
        }
        return nil
    }

    private func containsBlockChildren(_ element: Element) -> Bool {
        element.children().array().contains { blockTags.contains($0.tagName().lowercased()) }
    }

    private func headingStyle(for tag: String) -> String {
        switch tag {
        case "h1": return "Heading1"
        case "h2": return "Heading2"
        default: return "Heading3"
        }
    }

    private func normalizeInlineText(_ text: String, preserveWhitespace: Bool) -> String {
        let normalized = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return preserveWhitespace ? normalized : collapseSpaces(normalized)
    }

    private func collapseSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func appendTextRun(_ text: String, properties: RunProperties, to paragraph: inout Paragraph) {
        guard !text.isEmpty else { return }

        var value = text
        if paragraph.runs.isEmpty {
            value = value.replacingOccurrences(of: #"^\s+"#, with: "", options: .regularExpression)
        } else if let lastIndex = paragraph.runs.indices.last,
                  paragraph.runs[lastIndex].rawXML == nil,
                  paragraph.runs[lastIndex].drawing == nil {
            if paragraph.runs[lastIndex].text.hasSuffix(" "), value.hasPrefix(" ") {
                value.removeFirst()
            }
            if paragraph.runs[lastIndex].properties == properties {
                paragraph.runs[lastIndex].text += value
                return
            }
        }

        guard !value.isEmpty else { return }
        paragraph.runs.append(Run(text: value, properties: properties))
    }

    private func finalizeParagraph(_ paragraph: inout Paragraph) {
        var cleaned: [Run] = []
        for var run in paragraph.runs {
            if run.rawXML == nil, run.drawing == nil {
                if cleaned.isEmpty {
                    run.text = run.text.replacingOccurrences(of: #"^\s+"#, with: "", options: .regularExpression)
                }
                if run.text.isEmpty {
                    continue
                }
            }
            cleaned.append(run)
        }

        if let index = cleaned.lastIndex(where: { $0.rawXML == nil && $0.drawing == nil }) {
            cleaned[index].text = cleaned[index].text.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            if cleaned[index].text.isEmpty {
                cleaned.remove(at: index)
            }
        }

        paragraph.runs = cleaned
    }

    private func rawXMLRun(_ xml: String) -> Run {
        var run = Run(text: "")
        run.rawXML = xml
        return run
    }

    private func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private struct ListContext {
    let kind: ListKind
    let numId: Int
    let level: Int
}

private enum ListKind {
    case unordered
    case ordered
}

private let ignoredTags: Set<String> = [
    "script", "style", "noscript", "meta", "link", "head", "title"
]

private let blockTags: Set<String> = [
    "address", "article", "aside", "blockquote", "details", "div", "dl", "fieldset", "figcaption",
    "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "li",
    "main", "nav", "ol", "p", "pre", "section", "table", "ul"
]

private let containerTags: Set<String> = [
    "article", "body", "div", "figure", "figcaption", "main", "section", "span"
]
