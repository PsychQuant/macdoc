import Foundation
import CommonConverterSwift
import OOXMLSwift

public struct WordHTMLConverter: DocumentConverter {
    public static let sourceFormat = "docx"

    public init() {}

    public func convert<W: StreamingOutput>(
        input: URL,
        output: inout W,
        options: ConversionOptions
    ) throws {
        let document = try DocxReader.read(from: input)
        try convert(document: document, source: input, output: &output, options: options)
    }

    public func convert<W: StreamingOutput>(
        document: WordDocument,
        output: inout W,
        options: ConversionOptions = .default
    ) throws {
        try convert(document: document, source: nil, output: &output, options: options)
    }

    public func convertToString(
        document: WordDocument,
        options: ConversionOptions = .default
    ) throws -> String {
        var writer = StringOutput()
        try convert(document: document, output: &writer, options: options)
        return writer.content
    }

    private func convert<W: StreamingOutput>(
        document: WordDocument,
        source: URL?,
        output: inout W,
        options: ConversionOptions
    ) throws {
        var context = ConversionContext(document: document, options: options)
        let title = resolvedTitle(for: document, source: source)

        if options.includeFrontmatter {
            try emitFrontmatter(document: document, source: source, title: title, output: &output)
        }

        try emitDocumentStart(title: title, output: &output)

        let children = document.body.children
        var index = 0
        while index < children.count {
            switch children[index] {
            case .paragraph(let paragraph):
                if paragraph.properties.numbering != nil {
                    let (items, nextIndex) = collectListItems(children: children, startIndex: index, context: &context)
                    try emitListBlock(items, output: &output)
                    index = nextIndex
                } else {
                    try emitParagraph(paragraph, context: &context, output: &output)
                    index += 1
                }
            case .table(let table):
                try emitTable(table, context: &context, output: &output)
                index += 1
            }
        }

        try emitFootnotes(context: context, output: &output)
        try emitDocumentEnd(output: &output)
    }

    // MARK: - Document Shell

    private func emitFrontmatter<W: StreamingOutput>(
        document: WordDocument,
        source: URL?,
        title: String,
        output: inout W
    ) throws {
        try output.writeLine("<!--")
        try output.writeLine("format: docx")
        try output.writeLine("title: \(title)")
        if let source {
            try output.writeLine("source: \(source.lastPathComponent)")
        }
        if let author = document.properties.creator, !author.isEmpty {
            try output.writeLine("author: \(author)")
        }
        try output.writeLine("-->")
    }

    private func emitDocumentStart<W: StreamingOutput>(
        title: String,
        output: inout W
    ) throws {
        try output.writeLine("<!DOCTYPE html>")
        try output.writeLine("<html lang=\"en\">")
        try output.writeLine("<head>")
        try output.writeLine("  <meta charset=\"utf-8\" />")
        try output.writeLine("  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />")
        try output.writeLine("  <meta name=\"generator\" content=\"word-to-html-swift\" />")
        try output.writeLine("  <title>\(escapeHTML(title))</title>")
        try output.writeLine("  <style>")
        for line in stylesheet.components(separatedBy: .newlines) {
            try output.writeLine(line)
        }
        try output.writeLine("  </style>")
        try output.writeLine("</head>")
        try output.writeLine("<body>")
        try output.writeLine("  <main class=\"document\">")
    }

    private func emitDocumentEnd<W: StreamingOutput>(output: inout W) throws {
        try output.writeLine("  </main>")
        try output.writeLine("</body>")
        try output.writeLine("</html>")
    }

    // MARK: - Blocks

    private func emitParagraph<W: StreamingOutput>(
        _ paragraph: Paragraph,
        context: inout ConversionContext,
        output: inout W
    ) throws {
        if paragraph.hasPageBreak || paragraph.properties.pageBreakBefore {
            try output.writeLine("    <hr />")
            if paragraph.runs.isEmpty && paragraph.hyperlinks.isEmpty {
                return
            }
        }

        if let styleName = paragraph.properties.style,
           isCodeStyle(styleName, styles: context.styles) {
            let plain = escapeHTML(collectPlainText(paragraph))
            guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            try output.writeLine("    <pre><code>\(plain)</code></pre>")
            return
        }

        let html = renderParagraphContent(paragraph, context: &context)
        guard !isHTMLContentEmpty(html) else { return }

        if let styleName = paragraph.properties.style,
           isBlockquoteStyle(styleName, styles: context.styles) {
            try output.writeLine("    <blockquote><p>\(html)</p></blockquote>")
            return
        }

        if let styleName = paragraph.properties.style,
           let level = detectHeadingLevel(styleName: styleName, styles: context.styles) {
            let clamped = max(1, min(level, 6))
            try output.writeLine("    <h\(clamped)>\(html)</h\(clamped)>")
            return
        }

        try output.writeLine("    <p>\(html)</p>")
    }

    private func emitTable<W: StreamingOutput>(
        _ table: Table,
        context: inout ConversionContext,
        output: inout W
    ) throws {
        guard !table.rows.isEmpty else { return }

        try output.writeLine("    <table>")

        if let headerRow = table.rows.first {
            try output.writeLine("      <thead>")
            try output.writeLine("        <tr>")
            for cell in headerRow.cells {
                let content = renderTableCell(cell, context: &context)
                try output.writeLine("          <th>\(content)</th>")
            }
            try output.writeLine("        </tr>")
            try output.writeLine("      </thead>")
        }

        if table.rows.count > 1 {
            try output.writeLine("      <tbody>")
            for row in table.rows.dropFirst() {
                try output.writeLine("        <tr>")
                for cell in row.cells {
                    let content = renderTableCell(cell, context: &context)
                    try output.writeLine("          <td>\(content)</td>")
                }
                try output.writeLine("        </tr>")
            }
            try output.writeLine("      </tbody>")
        }

        try output.writeLine("    </table>")
    }

    private func renderTableCell(
        _ cell: TableCell,
        context: inout ConversionContext
    ) -> String {
        let joined = cell.paragraphs
            .map { renderParagraphContent($0, context: &context) }
            .filter { !isHTMLContentEmpty($0) }
            .joined(separator: "<br />")
        return joined.isEmpty ? "&nbsp;" : joined
    }

    // MARK: - Lists

    private func collectListItems(
        children: [BodyChild],
        startIndex: Int,
        context: inout ConversionContext
    ) -> ([FlatListItem], Int) {
        var items: [FlatListItem] = []
        var index = startIndex

        while index < children.count {
            guard case .paragraph(let paragraph) = children[index],
                  let numInfo = paragraph.properties.numbering else {
                break
            }

            let kind: ListKind = isListBullet(
                numId: numInfo.numId,
                level: numInfo.level,
                numbering: context.numbering
            ) ? .unordered : .ordered

            let html = renderParagraphContent(paragraph, context: &context)
            items.append(
                FlatListItem(
                    kind: kind,
                    level: max(0, numInfo.level),
                    content: html.isEmpty ? "&nbsp;" : html
                )
            )
            index += 1
        }

        return (normalizeListLevels(items), index)
    }

    private func normalizeListLevels(_ items: [FlatListItem]) -> [FlatListItem] {
        guard let minLevel = items.map(\.level).min() else { return items }
        return items.map { item in
            FlatListItem(kind: item.kind, level: max(0, item.level - minLevel), content: item.content)
        }
    }

    private func emitListBlock<W: StreamingOutput>(
        _ items: [FlatListItem],
        output: inout W
    ) throws {
        guard !items.isEmpty else { return }
        var index = 0
        while index < items.count {
            try renderList(items: items, index: &index, level: items[index].level, kind: items[index].kind, output: &output)
        }
    }

    private func renderList<W: StreamingOutput>(
        items: [FlatListItem],
        index: inout Int,
        level: Int,
        kind: ListKind,
        output: inout W
    ) throws {
        let indent = String(repeating: "  ", count: level + 2)
        let itemIndent = String(repeating: "  ", count: level + 3)

        try output.writeLine("\(indent)<\(kind.tagName)>")
        while index < items.count {
            let item = items[index]
            if item.level < level { break }
            if item.level != level || item.kind != kind { break }

            try output.write("\(itemIndent)<li>\(item.content)")
            index += 1

            while index < items.count, items[index].level > level {
                try output.writeLine("")
                try renderList(items: items, index: &index, level: items[index].level, kind: items[index].kind, output: &output)
                try output.write("\(itemIndent)")
            }

            try output.writeLine("</li>")
        }
        try output.writeLine("\(indent)</\(kind.tagName)>")
    }

    // MARK: - Inlines

    private func renderParagraphContent(
        _ paragraph: Paragraph,
        context: inout ConversionContext
    ) -> String {
        var result = ""

        for run in paragraph.runs {
            result += renderRun(run, context: &context)
        }

        for hyperlink in paragraph.hyperlinks {
            result += renderHyperlink(hyperlink, context: context)
        }

        for footnoteId in paragraph.footnoteIds {
            context.registerFootnote(id: footnoteId)
            let id = escapeAttribute("fn-\(footnoteId)")
            let refId = escapeAttribute("fnref-\(footnoteId)")
            result += "<sup class=\"footnote-ref\"><a id=\"\(refId)\" href=\"#\(id)\">\(footnoteId)</a></sup>"
        }

        for endnoteId in paragraph.endnoteIds {
            let mappedId = "en\(endnoteId)"
            context.registerEndnote(id: endnoteId, mappedId: mappedId)
            let id = escapeAttribute("fn-\(mappedId)")
            let refId = escapeAttribute("fnref-\(mappedId)")
            result += "<sup class=\"footnote-ref\"><a id=\"\(refId)\" href=\"#\(id)\">\(escapeHTML(mappedId))</a></sup>"
        }

        return result
    }

    private func renderRun(
        _ run: Run,
        context: inout ConversionContext
    ) -> String {
        if let drawing = run.drawing {
            return renderDrawing(drawing, context: &context)
        }

        guard !run.text.isEmpty else { return "" }

        var text = escapeHTML(run.text)
        let props = run.properties

        if let semantic = run.semantic,
           case .formula = semantic.type {
            return "<span class=\"formula\">\(text)</span>"
        }

        if props.bold && props.italic {
            text = "<strong><em>\(text)</em></strong>"
        } else if props.bold {
            text = "<strong>\(text)</strong>"
        } else if props.italic {
            text = "<em>\(text)</em>"
        }

        if props.strikethrough {
            text = "<del>\(text)</del>"
        }

        if props.underline != nil {
            text = "<u>\(text)</u>"
        }
        if props.verticalAlign == .superscript {
            text = "<sup>\(text)</sup>"
        }
        if props.verticalAlign == .subscript {
            text = "<sub>\(text)</sub>"
        }
        if props.highlight != nil {
            text = "<mark>\(text)</mark>"
        }

        return text.replacingOccurrences(of: "\n", with: context.options.hardLineBreaks ? "<br />" : "\n")
    }

    private func renderHyperlink(
        _ hyperlink: Hyperlink,
        context: ConversionContext
    ) -> String {
        let label = escapeHTML(hyperlink.text)

        switch hyperlink.type {
        case .external:
            if let url = hyperlink.url, !url.isEmpty {
                return "<a href=\"\(escapeAttribute(url))\">\(label.isEmpty ? escapeHTML(url) : label)</a>"
            }
            if let relationshipId = hyperlink.relationshipId,
               let reference = context.document.hyperlinkReferences.first(where: { $0.relationshipId == relationshipId }) {
                let url = reference.url
                return "<a href=\"\(escapeAttribute(url))\">\(label.isEmpty ? escapeHTML(url) : label)</a>"
            }
            return label

        case .internal:
            if let anchor = hyperlink.anchor, !anchor.isEmpty {
                return "<a href=\"#\(escapeAttribute(anchor))\">\(label)</a>"
            }
            return label
        }
    }

    private func renderDrawing(
        _ drawing: Drawing,
        context: inout ConversionContext
    ) -> String {
        let imageRef = context.document.images.first { $0.id == drawing.imageId }
        let alt = escapeAttribute(drawing.description.isEmpty ? drawing.name : drawing.description)
        let src = resolveImageSource(imageRef: imageRef, options: context.options) ?? drawing.imageId
        return "<img src=\"\(escapeAttribute(src))\" alt=\"\(alt)\" />"
    }

    private func resolveImageSource(imageRef: ImageReference?, options: ConversionOptions) -> String? {
        guard let imageRef else { return nil }

        if let figuresDirectory = options.figuresDirectory {
            try? FileManager.default.createDirectory(at: figuresDirectory, withIntermediateDirectories: true)
            let targetURL = figuresDirectory.appendingPathComponent(imageRef.fileName)
            if !FileManager.default.fileExists(atPath: targetURL.path) {
                try? imageRef.data.write(to: targetURL)
            }
            return figuresDirectory.lastPathComponent + "/" + imageRef.fileName
        }

        return imageRef.fileName
    }

    // MARK: - Footnotes

    private func emitFootnotes<W: StreamingOutput>(
        context: ConversionContext,
        output: inout W
    ) throws {
        let hasFootnotes = !context.referencedFootnoteIds.isEmpty
        let hasEndnotes = !context.referencedEndnoteIds.isEmpty
        guard hasFootnotes || hasEndnotes else { return }

        try output.writeLine("    <section class=\"footnotes\">")
        try output.writeLine("      <hr />")
        try output.writeLine("      <ol>")

        for id in context.referencedFootnoteIds.sorted() {
            if let footnote = context.document.footnotes.footnotes.first(where: { $0.id == id }) {
                let escapedText = escapeHTML(footnote.text)
                let liId = escapeAttribute("fn-\(id)")
                let refId = escapeAttribute("fnref-\(id)")
                try output.writeLine("        <li id=\"\(liId)\"><p>\(escapedText) <a class=\"footnote-backref\" href=\"#\(refId)\">↩</a></p></li>")
            }
        }

        for (id, mappedId) in context.endnoteIdMapping.sorted(by: { $0.key < $1.key }) {
            if let endnote = context.document.endnotes.endnotes.first(where: { $0.id == id }) {
                let escapedText = escapeHTML(endnote.text)
                let liId = escapeAttribute("fn-\(mappedId)")
                let refId = escapeAttribute("fnref-\(mappedId)")
                try output.writeLine("        <li id=\"\(liId)\"><p>\(escapedText) <a class=\"footnote-backref\" href=\"#\(refId)\">↩</a></p></li>")
            }
        }

        try output.writeLine("      </ol>")
        try output.writeLine("    </section>")
    }

    // MARK: - Helpers

    private func resolvedTitle(for document: WordDocument, source: URL?) -> String {
        if let title = document.properties.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let source {
            return source.deletingPathExtension().lastPathComponent
        }
        return "Document"
    }

    private func collectPlainText(_ paragraph: Paragraph) -> String {
        var text = paragraph.runs.map(\.text).joined()
        for hyperlink in paragraph.hyperlinks {
            text += hyperlink.text
        }
        return text
    }

    private func isHTMLContentEmpty(_ html: String) -> Bool {
        let withoutTags = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let normalized = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty
    }

    private func isCodeStyle(_ styleName: String, styles: [Style]) -> Bool {
        let lower = styleName.lowercased()
        let codePatterns = ["code", "source", "listing", "verbatim", "preformatted"]
        if codePatterns.contains(where: { lower.contains($0) }) {
            return true
        }
        if let style = styles.first(where: { $0.id.lowercased() == lower }),
           let basedOn = style.basedOn {
            return isCodeStyle(basedOn, styles: styles)
        }
        return false
    }

    private func isBlockquoteStyle(_ styleName: String, styles: [Style]) -> Bool {
        let lower = styleName.lowercased()
        let quotePatterns = ["quote", "block text"]
        if quotePatterns.contains(where: { lower.contains($0) }) {
            return true
        }
        if let style = styles.first(where: { $0.id.lowercased() == lower }),
           let basedOn = style.basedOn {
            return isBlockquoteStyle(basedOn, styles: styles)
        }
        return false
    }

    private func detectHeadingLevel(styleName: String, styles: [Style]) -> Int? {
        let lower = styleName.lowercased()
        let patterns: [(String, Int)] = [
            ("heading1", 1), ("heading 1", 1), ("標題 1", 1), ("標題1", 1),
            ("heading2", 2), ("heading 2", 2), ("標題 2", 2), ("標題2", 2),
            ("heading3", 3), ("heading 3", 3), ("標題 3", 3), ("標題3", 3),
            ("heading4", 4), ("heading 4", 4), ("標題 4", 4), ("標題4", 4),
            ("heading5", 5), ("heading 5", 5), ("標題 5", 5), ("標題5", 5),
            ("heading6", 6), ("heading 6", 6), ("標題 6", 6), ("標題6", 6),
            ("title", 1), ("subtitle", 2),
        ]

        for (pattern, level) in patterns where lower == pattern {
            return level
        }

        if let style = styles.first(where: { $0.id.lowercased() == lower }),
           let basedOn = style.basedOn {
            return detectHeadingLevel(styleName: basedOn, styles: styles)
        }
        return nil
    }

    private func isListBullet(numId: Int, level: Int, numbering: Numbering) -> Bool {
        guard let num = numbering.nums.first(where: { $0.numId == numId }) else {
            return true
        }
        guard let abstractNum = numbering.abstractNums.first(where: { $0.abstractNumId == num.abstractNumId }) else {
            return true
        }
        guard let levelDef = abstractNum.levels.first(where: { $0.ilvl == level }) else {
            return true
        }
        return levelDef.numFmt == .bullet
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func escapeAttribute(_ text: String) -> String {
        escapeHTML(text)
    }

    private let stylesheet = """
    body {
      margin: 0;
      background: #ffffff;
      color: #111827;
      font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif;
      line-height: 1.65;
    }
    .document {
      max-width: 860px;
      margin: 0 auto;
      padding: 40px 24px 72px;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      margin: 1.25rem 0;
    }
    th, td {
      border: 1px solid #d1d5db;
      padding: 0.5rem 0.75rem;
      vertical-align: top;
      text-align: left;
    }
    blockquote {
      margin: 1.25rem 0;
      padding-left: 1rem;
      border-left: 4px solid #d1d5db;
      color: #374151;
    }
    pre {
      overflow-x: auto;
      padding: 0.875rem 1rem;
      border-radius: 10px;
      background: #111827;
      color: #f9fafb;
    }
    code {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    }
    img {
      max-width: 100%;
      height: auto;
    }
    .footnotes {
      margin-top: 2.5rem;
      color: #374151;
      font-size: 0.95rem;
    }
    .footnote-ref {
      font-size: 0.8em;
    }
    """
}

private struct ConversionContext {
    let document: WordDocument
    let options: ConversionOptions
    var styles: [Style] { document.styles }
    var numbering: Numbering { document.numbering }
    var referencedFootnoteIds: Set<Int> = []
    var referencedEndnoteIds: Set<Int> = []
    var endnoteIdMapping: [Int: String] = [:]

    mutating func registerFootnote(id: Int) {
        referencedFootnoteIds.insert(id)
    }

    mutating func registerEndnote(id: Int, mappedId: String) {
        referencedEndnoteIds.insert(id)
        endnoteIdMapping[id] = mappedId
    }
}

private struct FlatListItem {
    let kind: ListKind
    let level: Int
    let content: String
}

private enum ListKind {
    case unordered
    case ordered

    var tagName: String {
        switch self {
        case .unordered: return "ul"
        case .ordered: return "ol"
        }
    }
}
