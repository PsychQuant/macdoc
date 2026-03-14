import Foundation
import Markdown
import DocConverterSwift
import OOXMLSwift

private typealias WordParagraph = OOXMLSwift.Paragraph

/// Direct Markdown → Word (.docx) converter.
///
/// The streaming `DocumentConverter` surface writes `word/document.xml` so callers can
/// inspect the generated OOXML without materializing an archive. Use `convertToFile`
/// for full `.docx` output.
public struct MarkdownToWordConverter: DocumentConverter {
    public static let sourceFormat = "md"

    public init() {}

    public func convert<W: DocConverterSwift.StreamingOutput>(
        input: URL,
        output: inout W,
        options: ConversionOptions
    ) throws {
        let document = try convertToDocument(input: input, options: options)
        try output.write(renderDocumentXML(document))
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
        let source = try loadSource(from: input)
        return try convertMarkdown(
            source,
            baseURL: input.deletingLastPathComponent(),
            sourceName: input.lastPathComponent,
            options: options
        )
    }

    public func convertMarkdown(
        _ source: String,
        baseURL: URL? = nil,
        sourceName: String? = nil,
        options: ConversionOptions = .default
    ) throws -> WordDocument {
        let extracted = FrontmatterExtractor.extract(from: source)
        var builder = MarkdownWordBuilder(
            options: options,
            baseURL: baseURL,
            sourceName: sourceName,
            frontmatter: extracted.metadata
        )
        return try builder.build(markdown: extracted.body)
    }

    private func renderDocumentXML(_ document: WordDocument) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <w:body>
        """

        for child in document.body.children {
            switch child {
            case .paragraph(let paragraph):
                xml += paragraph.toXML()
            case .table(let table):
                xml += table.toXML()
            }
        }

        xml += renderSectionPropertiesXML(document.sectionProperties)
        xml += "</w:body></w:document>"
        return xml
    }

    private func renderSectionPropertiesXML(_ section: SectionProperties) -> String {
        var xml = "<w:sectPr>"

        if let headerReference = section.headerReference {
            xml += "<w:headerReference w:type=\"default\" r:id=\"\(headerReference)\"/>"
        }
        if let footerReference = section.footerReference {
            xml += "<w:footerReference w:type=\"default\" r:id=\"\(footerReference)\"/>"
        }

        var pageSizeAttributes = "w:w=\"\(section.pageSize.width)\" w:h=\"\(section.pageSize.height)\""
        if section.orientation == .landscape {
            pageSizeAttributes += " w:orient=\"landscape\""
        }
        xml += "<w:pgSz \(pageSizeAttributes)/>"
        xml += "<w:pgMar w:top=\"\(section.pageMargins.top)\" w:right=\"\(section.pageMargins.right)\" w:bottom=\"\(section.pageMargins.bottom)\" w:left=\"\(section.pageMargins.left)\" w:header=\"\(section.pageMargins.header)\" w:footer=\"\(section.pageMargins.footer)\" w:gutter=\"\(section.pageMargins.gutter)\"/>"
        xml += "<w:cols w:space=\"720\" w:num=\"\(section.columns)\"/>"

        if let grid = section.docGrid {
            var gridAttributes = "w:linePitch=\"\(grid.linePitch)\""
            if let charSpace = grid.charSpace {
                gridAttributes += " w:charSpace=\"\(charSpace)\""
            }
            xml += "<w:docGrid \(gridAttributes)/>"
        } else {
            xml += "<w:docGrid w:linePitch=\"360\"/>"
        }

        xml += "</w:sectPr>"
        return xml
    }

    private func loadSource(from input: URL) throws -> String {
        do {
            return try String(contentsOf: input, encoding: .utf8)
        } catch let error as CocoaError
            where error.code == .fileReadNoSuchFile
            || error.code == .fileReadNoPermission
            || error.code == .fileNoSuchFile {
            throw error
        } catch {
            if let latin1 = try? String(contentsOf: input, encoding: .isoLatin1) {
                return latin1
            }
            return try String(contentsOf: input, encoding: .utf8)
        }
    }
}

public typealias MarkdownDOCXConverter = MarkdownToWordConverter

private struct MarkdownWordBuilder {
    private(set) var document = WordDocument()
    private let options: ConversionOptions
    private let baseURL: URL?
    private let sourceName: String?
    private let frontmatter: [String: String]
    private var inferredTitle = false

    init(
        options: ConversionOptions,
        baseURL: URL?,
        sourceName: String?,
        frontmatter: [String: String]
    ) {
        self.options = options
        self.baseURL = baseURL
        self.sourceName = sourceName
        self.frontmatter = frontmatter
    }

    mutating func build(markdown: String) throws -> WordDocument {
        applyDocumentMetadata()

        let parsed = Document(parsing: markdown, options: .parseBlockDirectives)
        for child in parsed.children {
            try appendBlock(child, quoteDepth: 0)
        }

        if document.body.children.isEmpty {
            document.appendParagraph(WordParagraph(text: ""))
        }

        return document
    }

    private mutating func applyDocumentMetadata() {
        document.properties.creator = frontmatter["author"] ?? frontmatter["creator"] ?? "macdoc"
        document.properties.subject = frontmatter["subject"]
        document.properties.keywords = frontmatter["keywords"]
        document.properties.description = frontmatter["description"]
            ?? sourceName.map { "Converted from Markdown file \($0)" }
        document.properties.title = frontmatter["title"]
        document.properties.created = Date()
        document.properties.modified = Date()
    }

    private mutating func appendBlock(_ markup: Markup, quoteDepth: Int) throws {
        switch markup {
        case let heading as Markdown.Heading:
            try appendHeading(heading, quoteDepth: quoteDepth)
        case let paragraph as Markdown.Paragraph:
            if let converted = try makeParagraph(from: paragraph, quoteDepth: quoteDepth) {
                document.appendParagraph(converted)
            }
        case let blockQuote as Markdown.BlockQuote:
            for child in blockQuote.children {
                try appendBlock(child, quoteDepth: quoteDepth + 1)
            }
        case let orderedList as Markdown.OrderedList:
            try appendOrderedList(orderedList, level: 0, quoteDepth: quoteDepth)
        case let unorderedList as Markdown.UnorderedList:
            try appendUnorderedList(unorderedList, level: 0, quoteDepth: quoteDepth)
        case let codeBlock as Markdown.CodeBlock:
            appendCodeBlock(codeBlock, quoteDepth: quoteDepth, extraIndentLevels: 0)
        case let table as Markdown.Table:
            if let converted = try makeTable(from: table) {
                document.appendTable(converted)
            }
        case _ as Markdown.ThematicBreak:
            appendHorizontalRule(quoteDepth: quoteDepth)
        default:
            for child in markup.children {
                try appendBlock(child, quoteDepth: quoteDepth)
            }
        }
    }

    private mutating func appendHeading(_ heading: Markdown.Heading, quoteDepth: Int) throws {
        guard let paragraph = try makeParagraph(
            fromInlineChildren: Array(heading.children),
            quoteDepth: quoteDepth,
            style: headingStyleID(for: heading.level)
        ) else {
            return
        }

        if !inferredTitle, document.properties.title == nil {
            let title = paragraph.getText().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !title.isEmpty {
                document.properties.title = title
                inferredTitle = true
            }
        }

        document.appendParagraph(paragraph)
    }

    private mutating func appendOrderedList(
        _ list: Markdown.OrderedList,
        level: Int,
        quoteDepth: Int
    ) throws {
        let numId = document.numbering.createNumberedList()
        for child in list.children {
            guard let item = child as? Markdown.ListItem else { continue }
            try appendListItem(item, numId: numId, level: level, quoteDepth: quoteDepth)
        }
    }

    private mutating func appendUnorderedList(
        _ list: Markdown.UnorderedList,
        level: Int,
        quoteDepth: Int
    ) throws {
        let numId = document.numbering.createBulletList()
        for child in list.children {
            guard let item = child as? Markdown.ListItem else { continue }
            try appendListItem(item, numId: numId, level: level, quoteDepth: quoteDepth)
        }
    }

    private mutating func appendListItem(
        _ item: Markdown.ListItem,
        numId: Int,
        level: Int,
        quoteDepth: Int
    ) throws {
        var emittedPrimaryParagraph = false

        for child in item.children {
            switch child {
            case let paragraph as Markdown.Paragraph:
                let numbering = emittedPrimaryParagraph ? nil : NumberingInfo(numId: numId, level: min(level, 8))
                let extraIndentLevels = emittedPrimaryParagraph ? level + 1 : 0
                if let converted = try makeParagraph(
                    from: paragraph,
                    quoteDepth: quoteDepth,
                    numbering: numbering,
                    extraIndentLevels: extraIndentLevels
                ) {
                    document.appendParagraph(converted)
                    emittedPrimaryParagraph = true
                }
            case let nestedOrdered as Markdown.OrderedList:
                try appendOrderedList(nestedOrdered, level: level + 1, quoteDepth: quoteDepth)
            case let nestedUnordered as Markdown.UnorderedList:
                try appendUnorderedList(nestedUnordered, level: level + 1, quoteDepth: quoteDepth)
            case let codeBlock as Markdown.CodeBlock:
                appendCodeBlock(codeBlock, quoteDepth: quoteDepth, extraIndentLevels: level + 1)
            case let blockQuote as Markdown.BlockQuote:
                for grandchild in blockQuote.children {
                    try appendBlock(grandchild, quoteDepth: quoteDepth + 1)
                }
            case let table as Markdown.Table:
                if let converted = try makeTable(from: table) {
                    document.appendTable(converted)
                }
            case let heading as Markdown.Heading:
                guard let converted = try makeParagraph(
                    fromInlineChildren: Array(heading.children),
                    quoteDepth: quoteDepth,
                    numbering: emittedPrimaryParagraph ? nil : NumberingInfo(numId: numId, level: min(level, 8)),
                    extraIndentLevels: emittedPrimaryParagraph ? level + 1 : 0,
                    style: headingStyleID(for: heading.level)
                ) else {
                    continue
                }
                document.appendParagraph(converted)
                emittedPrimaryParagraph = true
            default:
                try appendBlock(child, quoteDepth: quoteDepth)
            }
        }
    }

    private mutating func appendCodeBlock(
        _ codeBlock: Markdown.CodeBlock,
        quoteDepth: Int,
        extraIndentLevels: Int
    ) {
        let code = codeBlock.code
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = code.components(separatedBy: .newlines)

        if lines.isEmpty {
            var paragraph = WordParagraph(text: "")
            applyCodeStyle(to: &paragraph, quoteDepth: quoteDepth, extraIndentLevels: extraIndentLevels)
            document.appendParagraph(paragraph)
            return
        }

        for line in lines {
            var runProps = RunProperties()
            runProps.fontName = "Menlo"
            runProps.fontSize = 20
            let paragraph = WordParagraph(runs: [Run(text: line, properties: runProps)])
            var styled = paragraph
            applyCodeStyle(to: &styled, quoteDepth: quoteDepth, extraIndentLevels: extraIndentLevels)
            document.appendParagraph(styled)
        }
    }

    private mutating func appendHorizontalRule(quoteDepth: Int) {
        var paragraph = WordParagraph(text: "")
        paragraph.properties.spacing = Spacing(before: 120, after: 120)
        paragraph.properties.border = ParagraphBorder(
            bottom: ParagraphBorderStyle(type: .single, color: "C8C8C8", size: 8, space: 1)
        )
        applyQuoteStyle(to: &paragraph.properties, quoteDepth: quoteDepth, extraIndentLevels: 0)
        document.appendParagraph(paragraph)
    }

    private mutating func makeParagraph(
        from paragraph: Markdown.Paragraph,
        quoteDepth: Int,
        numbering: NumberingInfo? = nil,
        extraIndentLevels: Int = 0,
        style: String? = nil
    ) throws -> WordParagraph? {
        try makeParagraph(
            fromInlineChildren: Array(paragraph.children),
            quoteDepth: quoteDepth,
            numbering: numbering,
            extraIndentLevels: extraIndentLevels,
            style: style
        )
    }

    private mutating func makeParagraph(
        fromInlineChildren children: [Markup],
        quoteDepth: Int,
        numbering: NumberingInfo? = nil,
        extraIndentLevels: Int = 0,
        style: String? = nil
    ) throws -> WordParagraph? {
        var runs: [Run] = []
        for child in children {
            try appendInline(from: child, into: &runs, properties: RunProperties())
        }
        runs = coalesceRuns(runs)

        let textualContent = runs
            .filter { $0.rawXML == nil && $0.drawing == nil }
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if textualContent.isEmpty && runs.isEmpty {
            return nil
        }

        var paragraph = WordParagraph(runs: runs)
        paragraph.properties.style = style
        paragraph.properties.numbering = numbering
        paragraph.properties.spacing = Spacing(after: numbering == nil ? 200 : 80, line: 276, lineRule: .auto)
        applyQuoteStyle(to: &paragraph.properties, quoteDepth: quoteDepth, extraIndentLevels: extraIndentLevels)
        return paragraph
    }

    private mutating func appendInline(
        from markup: Markup,
        into runs: inout [Run],
        properties: RunProperties
    ) throws {
        switch markup {
        case let text as Text:
            guard !text.string.isEmpty else { return }
            runs.append(Run(text: text.string, properties: properties))

        case let emphasis as Emphasis:
            var next = properties
            next.italic = true
            for child in emphasis.children {
                try appendInline(from: child, into: &runs, properties: next)
            }

        case let strong as Strong:
            var next = properties
            next.bold = true
            for child in strong.children {
                try appendInline(from: child, into: &runs, properties: next)
            }

        case let strikethrough as Strikethrough:
            var next = properties
            next.strikethrough = true
            for child in strikethrough.children {
                try appendInline(from: child, into: &runs, properties: next)
            }

        case let inlineCode as InlineCode:
            var next = properties
            next.fontName = "Menlo"
            next.highlight = .lightGray
            runs.append(Run(text: inlineCode.code, properties: next))

        case _ as SoftBreak:
            if options.hardLineBreaks {
                runs.append(makeBreakRun())
            } else {
                runs.append(Run(text: " ", properties: properties))
            }

        case _ as LineBreak:
            runs.append(makeBreakRun())

        case let link as Link:
            let text = plainText(from: link).isEmpty ? (link.destination ?? "") : plainText(from: link)
            guard !text.isEmpty else { return }

            if let destination = link.destination, !destination.isEmpty {
                if destination.hasPrefix("#") {
                    let anchor = String(destination.dropFirst())
                    runs.append(makeRawRun(makeInternalHyperlinkXML(text: text, anchor: anchor)))
                } else {
                    let relationshipId = nextHyperlinkRelationshipID()
                    document.hyperlinkReferences.append(
                        HyperlinkReference(relationshipId: relationshipId, url: destination)
                    )
                    runs.append(
                        makeRawRun(
                            makeExternalHyperlinkXML(
                                text: text,
                                relationshipId: relationshipId
                            )
                        )
                    )
                }
            } else {
                runs.append(Run(text: text, properties: properties))
            }

        case let image as Image:
            let fallback = image.plainText.isEmpty
                ? "[Image: \(image.source ?? "image")]"
                : "[Image: \(image.plainText)]"
            var next = properties
            next.italic = true
            runs.append(Run(text: fallback, properties: next))

        case let inlineHTML as InlineHTML:
            let stripped = stripHTML(from: inlineHTML.rawHTML)
            guard !stripped.isEmpty else { return }
            runs.append(Run(text: stripped, properties: properties))

        default:
            for child in markup.children {
                try appendInline(from: child, into: &runs, properties: properties)
            }
        }
    }

    private mutating func makeTable(from table: Markdown.Table) throws -> OOXMLSwift.Table? {
        var rows: [TableRow] = []

        for child in table.children {
            if let head = child as? Markdown.Table.Head {
                rows.append(try makeTableHeaderRow(from: head))
            } else if let body = child as? Markdown.Table.Body {
                for row in body.children {
                    if let row = row as? Markdown.Table.Row {
                        rows.append(try makeTableRow(from: row, isHeader: false))
                    }
                }
            }
        }

        guard !rows.isEmpty else { return nil }

        var properties = TableProperties()
        properties.borders = TableBorders.all(Border(style: .single, size: 4, color: "BDBDBD"))
        properties.layout = .fixed
        properties.widthType = .auto

        return OOXMLSwift.Table(rows: rows, properties: properties)
    }

    private mutating func makeTableHeaderRow(
        from head: Markdown.Table.Head
    ) throws -> TableRow {
        var cells: [TableCell] = []
        for child in head.children {
            guard let cell = child as? Markdown.Table.Cell else { continue }
            let paragraph = try makeParagraph(
                fromInlineChildren: Array(cell.children),
                quoteDepth: 0
            ) ?? WordParagraph(text: "")

            var properties = TableCellProperties()
            properties.width = 2400
            properties.widthType = .dxa
            properties.shading = CellShading.solid("EFEFEF")
            cells.append(TableCell(paragraphs: [paragraph], properties: properties))
        }

        var props = TableRowProperties()
        props.isHeader = true
        return TableRow(cells: cells, properties: props)
    }

    private mutating func makeTableRow(
        from row: Markdown.Table.Row,
        isHeader: Bool
    ) throws -> TableRow {
        var cells: [TableCell] = []
        for child in row.children {
            guard let cell = child as? Markdown.Table.Cell else { continue }
            let paragraph = try makeParagraph(
                fromInlineChildren: Array(cell.children),
                quoteDepth: 0
            ) ?? WordParagraph(text: "")

            var properties = TableCellProperties()
            properties.width = 2400
            properties.widthType = .dxa
            if isHeader {
                properties.shading = CellShading.solid("EFEFEF")
            }

            cells.append(TableCell(paragraphs: [paragraph], properties: properties))
        }

        var props = TableRowProperties()
        props.isHeader = isHeader
        return TableRow(cells: cells, properties: props)
    }

    private func headingStyleID(for level: Int) -> String {
        switch level {
        case ...1: return "Heading1"
        case 2: return "Heading2"
        default: return "Heading3"
        }
    }

    private func nextHyperlinkRelationshipID() -> String {
        let baseID = document.numbering.abstractNums.isEmpty ? 4 : 5
        let usedCount = document.headers.count + document.footers.count + document.images.count + document.hyperlinkReferences.count
        return "rId\(baseID + usedCount)"
    }

    private func makeExternalHyperlinkXML(text: String, relationshipId: String) -> String {
        """
        <w:hyperlink r:id="\(relationshipId)">
            <w:r>
                <w:rPr>
                    <w:rStyle w:val="Hyperlink"/>
                    <w:color w:val="0563C1"/>
                    <w:u w:val="single"/>
                </w:rPr>
                <w:t xml:space="preserve">\(escapeXML(text))</w:t>
            </w:r>
        </w:hyperlink>
        """
    }

    private func makeInternalHyperlinkXML(text: String, anchor: String) -> String {
        """
        <w:hyperlink w:anchor="\(escapeXML(anchor))">
            <w:r>
                <w:rPr>
                    <w:rStyle w:val="Hyperlink"/>
                    <w:color w:val="0563C1"/>
                    <w:u w:val="single"/>
                </w:rPr>
                <w:t xml:space="preserve">\(escapeXML(text))</w:t>
            </w:r>
        </w:hyperlink>
        """
    }

    private func makeBreakRun() -> Run {
        makeRawRun("<w:r><w:br/></w:r>")
    }

    private func makeRawRun(_ rawXML: String) -> Run {
        var run = Run(text: "")
        run.rawXML = rawXML
        return run
    }

    private func plainText(from markup: Markup) -> String {
        switch markup {
        case let text as Text:
            return text.string
        case let inlineCode as InlineCode:
            return inlineCode.code
        case let softBreak as SoftBreak:
            _ = softBreak
            return options.hardLineBreaks ? "\n" : " "
        case let lineBreak as LineBreak:
            _ = lineBreak
            return "\n"
        case let image as Image:
            return image.plainText
        case let inlineHTML as InlineHTML:
            return stripHTML(from: inlineHTML.rawHTML)
        default:
            return markup.children.map(plainText).joined()
        }
    }

    private func stripHTML(from text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func applyCodeStyle(
        to paragraph: inout WordParagraph,
        quoteDepth: Int,
        extraIndentLevels: Int
    ) {
        paragraph.properties.spacing = Spacing(before: 0, after: 0)
        paragraph.properties.shading = CellShading.solid("F7F7F7")
        paragraph.properties.border = ParagraphBorder(
            left: ParagraphBorderStyle(type: .single, color: "D0D0D0", size: 6, space: 4)
        )
        applyQuoteStyle(to: &paragraph.properties, quoteDepth: quoteDepth, extraIndentLevels: extraIndentLevels)
    }

    private func applyQuoteStyle(
        to properties: inout ParagraphProperties,
        quoteDepth: Int,
        extraIndentLevels: Int
    ) {
        let totalIndent = max(0, quoteDepth * 720 + extraIndentLevels * 360)
        if totalIndent > 0 {
            properties.indentation = Indentation(left: totalIndent)
        }

        if quoteDepth > 0 {
            properties.border = ParagraphBorder(
                left: ParagraphBorderStyle(type: .single, color: "B0B0B0", size: 8, space: 4)
            )
            if properties.shading == nil {
                properties.shading = CellShading.solid("FAFAFA")
            }
        }
    }

    private func coalesceRuns(_ runs: [Run]) -> [Run] {
        var merged: [Run] = []
        for run in runs {
            guard let last = merged.last else {
                merged.append(run)
                continue
            }

            if canMerge(last, run) {
                var updated = merged.removeLast()
                updated.text += run.text
                merged.append(updated)
            } else {
                merged.append(run)
            }
        }
        return merged
    }

    private func canMerge(_ lhs: Run, _ rhs: Run) -> Bool {
        lhs.rawXML == nil
            && rhs.rawXML == nil
            && lhs.drawing == nil
            && rhs.drawing == nil
            && lhs.properties == rhs.properties
    }
}

private enum FrontmatterExtractor {
    static func extract(from source: String) -> (metadata: [String: String], body: String) {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard normalized.hasPrefix("---\n") else {
            return ([:], normalized)
        }

        let remainder = String(normalized.dropFirst(4))
        guard let closingRange = remainder.range(of: "\n---\n") else {
            return ([:], normalized)
        }

        let rawMetadata = String(remainder[..<closingRange.lowerBound])
        let body = String(remainder[closingRange.upperBound...])

        var metadata: [String: String] = [:]
        for line in rawMetadata.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let separator = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            if !key.isEmpty && !value.isEmpty {
                metadata[key] = value
            }
        }

        return (metadata, body)
    }
}
