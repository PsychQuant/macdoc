import Foundation
import PDFKit
import CommonConverterSwift
import OOXMLSwift

public struct PDFToDOCXConverter: DocumentConverter {
    public static let sourceFormat = "pdf"

    public init() {}

    public func convert<W: StreamingOutput>(
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
        guard FileManager.default.fileExists(atPath: input.path) else {
            throw ConversionError.fileNotFound(input.path)
        }
        guard let pdf = PDFDocument(url: input) else {
            throw ConversionError.invalidDocument("無法開啟 PDF：\(input.lastPathComponent)")
        }

        var builder = PDFWordBuilder(pdf: pdf, sourceURL: input, options: options)
        return builder.build()
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
}

public typealias PDFConverter = PDFToDOCXConverter

private struct PDFWordBuilder {
    private enum ListKind {
        case bullet
        case ordered
    }

    private let pdf: PDFDocument
    private let sourceURL: URL
    private let options: ConversionOptions
    private var document = WordDocument()

    init(pdf: PDFDocument, sourceURL: URL, options: ConversionOptions) {
        self.pdf = pdf
        self.sourceURL = sourceURL
        self.options = options
    }

    mutating func build() -> WordDocument {
        applyDocumentMetadata()

        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            if pageIndex > 0 {
                appendPageBreak()
            }
            emitPage(page, pageIndex: pageIndex)
        }

        if document.body.children.isEmpty {
            document.appendParagraph(Paragraph())
        }

        return document
    }

    private mutating func applyDocumentMetadata() {
        let attributes = pdf.documentAttributes ?? [:]
        document.properties.title = nonEmptyString(attributes[PDFDocumentAttribute.titleAttribute]) ?? inferTitle()
        document.properties.creator = nonEmptyString(attributes[PDFDocumentAttribute.authorAttribute])
            ?? nonEmptyString(attributes[PDFDocumentAttribute.creatorAttribute])
            ?? "macdoc"
        document.properties.subject = nonEmptyString(attributes[PDFDocumentAttribute.subjectAttribute])
            ?? sourceURL.lastPathComponent

        if let keywords = attributes[PDFDocumentAttribute.keywordsAttribute] as? [String], !keywords.isEmpty {
            document.properties.keywords = keywords.joined(separator: ", ")
        } else {
            document.properties.keywords = nonEmptyString(attributes[PDFDocumentAttribute.keywordsAttribute])
        }

        document.properties.description = "Converted from PDF file \(sourceURL.lastPathComponent)"
        document.properties.created = attributes[PDFDocumentAttribute.creationDateAttribute] as? Date ?? Date()
        document.properties.modified = attributes[PDFDocumentAttribute.modificationDateAttribute] as? Date ?? Date()
    }

    private mutating func emitPage(_ page: PDFPage, pageIndex: Int) {
        let blocks = splitIntoBlockCandidates(page.string ?? "")

        for (blockIndex, blockLines) in blocks.enumerated() {
            if let rows = detectTable(in: blockLines) {
                document.appendTable(makeTable(from: rows))
                continue
            }

            if let listKind = detectListKind(in: blockLines) {
                emitList(blockLines, kind: listKind)
                continue
            }

            let normalizedText = normalizeParagraphText(blockLines)
            guard !normalizedText.isEmpty else { continue }

            let properties: ParagraphProperties
            if let headingStyle = detectHeadingStyle(text: normalizedText, lines: blockLines, pageIndex: pageIndex, blockIndex: blockIndex) {
                var heading = ParagraphProperties()
                heading.style = headingStyle
                properties = heading
            } else {
                properties = ParagraphProperties()
            }

            document.appendParagraph(makeParagraph(lines: blockLines, properties: properties))
        }
    }

    private mutating func appendPageBreak() {
        var paragraph = Paragraph()
        paragraph.hasPageBreak = true
        paragraph.properties.pageBreakBefore = true
        document.appendParagraph(paragraph)
    }

    private mutating func emitList(_ lines: [String], kind: ListKind) {
        let numId = kind == .ordered
            ? document.numbering.createNumberedList()
            : document.numbering.createBulletList()

        for line in lines {
            let text = stripListMarker(from: line)
            guard !text.isEmpty else { continue }
            var properties = ParagraphProperties()
            properties.numbering = NumberingInfo(numId: numId, level: 0)
            document.appendParagraph(makeParagraph(lines: [text], properties: properties))
        }
    }

    private func makeParagraph(lines: [String], properties: ParagraphProperties) -> Paragraph {
        let normalizedLines = lines.map(normalizeInlineWhitespace).filter { !$0.isEmpty }
        if normalizedLines.isEmpty {
            return Paragraph(properties: properties)
        }

        if options.hardLineBreaks, normalizedLines.count > 1 {
            var runs: [Run] = []
            for (index, line) in normalizedLines.enumerated() {
                runs.append(Run(text: line))
                if index < normalizedLines.count - 1 {
                    var lineBreak = Run(text: "")
                    lineBreak.rawXML = "<w:r><w:br/></w:r>"
                    runs.append(lineBreak)
                }
            }
            return Paragraph(runs: runs, properties: properties)
        }

        let text = normalizedLines.joined(separator: " ")
        return Paragraph(text: text, properties: properties)
    }

    private func makeTable(from rows: [[String]]) -> Table {
        var properties = TableProperties()
        properties.borders = .all(Border(style: .single, size: 4, color: "808080"))
        properties.cellMargins = .all(80)
        properties.layout = .autofit

        let wordRows = rows.enumerated().map { rowIndex, cells in
            let wordCells = cells.map { cell -> TableCell in
                let paragraph = Paragraph(text: normalizeInlineWhitespace(cell))
                return TableCell(paragraphs: [paragraph])
            }
            var row = TableRow(cells: wordCells)
            row.properties.isHeader = rowIndex == 0
            return row
        }

        return Table(rows: wordRows, properties: properties)
    }

    private func splitIntoBlockCandidates(_ rawText: String) -> [[String]] {
        enum BlockKind: Equatable {
            case paragraph
            case table
            case bulletList
            case orderedList
        }

        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var blocks: [[String]] = []
        var current: [String] = []
        var currentKind: BlockKind?

        func flush() {
            guard !current.isEmpty else { return }
            blocks.append(current)
            current = []
            currentKind = nil
        }

        for line in normalized.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                flush()
                continue
            }

            let kind: BlockKind
            if isTableCandidateLine(trimmed) {
                kind = .table
            } else if isBulletListLine(trimmed) {
                kind = .bulletList
            } else if isOrderedListLine(trimmed) {
                kind = .orderedList
            } else {
                kind = .paragraph
            }

            if kind == .paragraph, isStandaloneHeadingLine(trimmed) {
                flush()
                blocks.append([trimmed])
                continue
            }

            if currentKind == nil || currentKind == kind {
                current.append(trimmed)
                currentKind = kind
            } else {
                flush()
                current.append(trimmed)
                currentKind = kind
            }

            if kind == .paragraph, looksLikeParagraphBoundary(trimmed) {
                flush()
            }
        }

        flush()
        return blocks
    }

    private func normalizeParagraphText(_ lines: [String]) -> String {
        lines
            .map(normalizeInlineWhitespace)
            .joined(separator: options.hardLineBreaks ? "\n" : " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeInlineWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func detectHeadingStyle(
        text: String,
        lines: [String],
        pageIndex: Int,
        blockIndex: Int
    ) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        let characterCount = trimmed.count
        let uppercaseLetters = trimmed.filter { $0.isLetter && $0.isUppercase }.count
        let letterCount = trimmed.filter(\.isLetter).count
        let uppercaseRatio = letterCount > 0 ? Double(uppercaseLetters) / Double(letterCount) : 0
        let endsLikeSentence = ".。!?！？:：;；".contains(trimmed.last ?? " ")
        let startsWithSectionNumber = trimmed.range(of: #"^(?:[0-9]+(?:\.[0-9]+)*|[IVXLCMivxlcm]+|[A-Z])[\.)]?\s+"#, options: .regularExpression) != nil
        let titlecaseWords = lines
            .joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .filter { !$0.isEmpty }
        let titlecaseRatio = titlecaseWords.isEmpty ? 0 : Double(titlecaseWords.filter(isHeadingLikeWord).count) / Double(titlecaseWords.count)

        if pageIndex == 0 && blockIndex == 0 && characterCount <= 140 {
            return "Heading1"
        }

        if wordCount <= 12 && characterCount <= 90 && !endsLikeSentence {
            if startsWithSectionNumber || uppercaseRatio >= 0.65 {
                return "Heading2"
            }

            if titlecaseRatio >= 0.7 {
                return "Heading2"
            }
        }

        if lines.count == 1,
           wordCount <= 6,
           characterCount <= 60,
           !endsLikeSentence,
           startsWithSectionNumber || uppercaseRatio >= 0.5 || titlecaseRatio >= 0.8 {
            return "Heading3"
        }

        return nil
    }

    private func isHeadingLikeWord(_ word: Substring) -> Bool {
        guard let scalar = word.unicodeScalars.first else { return false }
        if CharacterSet.decimalDigits.contains(scalar) {
            return true
        }
        let letters = word.filter(\.isLetter)
        guard let first = letters.first else { return false }
        return first.isUppercase || letters.allSatisfy(\.isUppercase)
    }

    private func isStandaloneHeadingLine(_ line: String) -> Bool {
        detectHeadingStyle(text: line, lines: [line], pageIndex: 1, blockIndex: 1) != nil
    }

    private func looksLikeParagraphBoundary(_ line: String) -> Bool {
        if let last = line.trimmingCharacters(in: .whitespacesAndNewlines).last,
           ".。!?！？:：;；".contains(last) {
            return true
        }
        return line.count >= 120
    }

    private func detectTable(in lines: [String]) -> [[String]]? {
        guard lines.count >= 2 else { return nil }
        let rows = lines.map(splitTableRow)
        guard let columnCount = rows.first?.count, columnCount >= 2 else { return nil }
        guard rows.allSatisfy({ $0.count == columnCount }) else { return nil }
        guard rows.allSatisfy({ $0.allSatisfy { !$0.isEmpty } }) else { return nil }
        return rows
    }

    private func isTableCandidateLine(_ line: String) -> Bool {
        line.contains("|") || line.contains("\t") || line.range(of: #" {3,}"#, options: .regularExpression) != nil
    }

    private func splitTableRow(_ line: String) -> [String] {
        let tabSeparated = line
            .replacingOccurrences(of: #"\s*\|\s*"#, with: "\t", options: .regularExpression)
            .replacingOccurrences(of: #" {3,}"#, with: "\t", options: .regularExpression)
            .replacingOccurrences(of: #"\t+"#, with: "\t", options: .regularExpression)

        return tabSeparated
            .components(separatedBy: "\t")
            .map(normalizeInlineWhitespace)
            .filter { !$0.isEmpty }
    }

    private func detectListKind(in lines: [String]) -> ListKind? {
        guard lines.count >= 2 else { return nil }

        if lines.allSatisfy(isBulletListLine) {
            return .bullet
        }
        if lines.allSatisfy(isOrderedListLine) {
            return .ordered
        }
        return nil
    }

    private func isBulletListLine(_ line: String) -> Bool {
        line.range(of: #"^(?:[•◦▪‣\-*])\s+"#, options: .regularExpression) != nil
    }

    private func isOrderedListLine(_ line: String) -> Bool {
        line.range(of: #"^(?:(?:\d+|[A-Za-z]|[IVXLCMivxlcm]+)[\.)])\s+"#, options: .regularExpression) != nil
    }

    private func stripListMarker(from line: String) -> String {
        let stripped = line.replacingOccurrences(
            of: #"^(?:[•◦▪‣\-*]|(?:\d+|[A-Za-z]|[IVXLCMivxlcm]+)[\.)])\s+"#,
            with: "",
            options: .regularExpression
        )
        return normalizeInlineWhitespace(stripped)
    }

    private func inferTitle() -> String {
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }
            let blocks = splitIntoBlockCandidates(page.string ?? "")
            if let first = blocks.first {
                let title = normalizeParagraphText(first)
                if !title.isEmpty && title.count <= 140 {
                    return title
                }
            }
        }
        return sourceURL.deletingPathExtension().lastPathComponent
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
