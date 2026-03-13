import Foundation
import Markdown
import DocConverterSwift

/// Converts Markdown files to HTML using Apple's swift-markdown parser.
public struct MarkdownConverter {
    public init() {}

    /// Convert a Markdown file to an HTML string.
    public func convert(input: URL, options: HTMLOptions = .default) throws -> String {
        let source = try loadSource(from: input)
        let document = Document(parsing: source, options: .parseBlockDirectives)
        var renderer = HTMLRenderer(options: options)
        return renderer.render(document)
    }

    /// Convert a Markdown string to HTML.
    public func convertString(_ markdown: String, options: HTMLOptions = .default) -> String {
        let document = Document(parsing: markdown, options: .parseBlockDirectives)
        var renderer = HTMLRenderer(options: options)
        return renderer.render(document)
    }

    // MARK: - File Loading

    /// Load file content, falling back to Latin-1 only on encoding errors.
    /// File-system errors (not found, no permission) are propagated immediately.
    private func loadSource(from input: URL) throws -> String {
        do {
            return try String(contentsOf: input, encoding: .utf8)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileReadNoPermission || error.code == .fileNoSuchFile {
            throw error
        } catch {
            // Only fall back to Latin-1 on encoding errors
            if let latin1 = try? String(contentsOf: input, encoding: .isoLatin1) {
                return latin1
            }
            return try String(contentsOf: input, encoding: .utf8)
        }
    }
}

// MARK: - Options

/// Options controlling the Markdown-to-HTML conversion.
public struct HTMLOptions {
    /// Whether to wrap output in a full `<html>` document.
    public var fullDocument: Bool
    /// CSS class prefix for generated elements.
    public var classPrefix: String
    /// Whether to render task-list checkboxes.
    public var taskListCheckboxes: Bool

    public static let `default` = HTMLOptions(
        fullDocument: false,
        classPrefix: "",
        taskListCheckboxes: true
    )

    public init(
        fullDocument: Bool = false,
        classPrefix: String = "",
        taskListCheckboxes: Bool = true
    ) {
        self.fullDocument = fullDocument
        self.classPrefix = classPrefix
        self.taskListCheckboxes = taskListCheckboxes
    }
}

// MARK: - HTML Renderer (MarkupWalker)

private struct HTMLRenderer: MarkupWalker {
    let options: HTMLOptions
    private var html = ""

    /// Column alignments for the current table being rendered.
    private var tableColumnAlignments: [Table.ColumnAlignment?]?
    /// Whether we are inside a table head.
    private var inTableHead = false
    /// Current column index while rendering cells.
    private var currentTableColumn = 0

    init(options: HTMLOptions) {
        self.options = options
    }

    mutating func render(_ document: Document) -> String {
        html = ""
        if options.fullDocument {
            html += "<!DOCTYPE html>\n<html>\n<head><meta charset=\"utf-8\"></head>\n<body>\n"
        }
        for child in document.children {
            visit(child)
        }
        if options.fullDocument {
            html += "</body>\n</html>\n"
        }
        return html
    }

    // MARK: - Block Elements

    mutating func visitHeading(_ heading: Heading) {
        let level = min(max(heading.level, 1), 6)
        html += "<h\(level)>"
        descendInto(heading)
        html += "</h\(level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        // Skip wrapping <p> if parent is a single-child list item (tight list).
        if let parent = paragraph.parent, parent is ListItem, parent.childCount == 1 {
            descendInto(paragraph)
            return
        }
        html += "<p>"
        descendInto(paragraph)
        html += "</p>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        html += "<blockquote>\n"
        for child in blockQuote.children {
            visit(child)
        }
        html += "</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let lang = codeBlock.language ?? ""
        if lang.isEmpty {
            html += "<pre><code>"
        } else {
            html += "<pre><code class=\"language-\(escapeAttribute(lang))\">"
        }
        html += escapeHTML(codeBlock.code)
        html += "</code></pre>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        html += "<hr>\n"
    }

    mutating func visitHTMLBlock(_ htmlBlock: HTMLBlock) {
        html += htmlBlock.rawHTML
    }

    // MARK: - Lists

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let start = orderedList.startIndex
        if start != 1 {
            html += "<ol start=\"\(start)\">\n"
        } else {
            html += "<ol>\n"
        }
        for child in orderedList.children {
            visit(child)
        }
        html += "</ol>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        html += "<ul>\n"
        for child in unorderedList.children {
            visit(child)
        }
        html += "</ul>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) {
        let checkbox = listItem.checkbox
        let isTask = checkbox != nil
        let children = Array(listItem.children)
        let isMultiBlock = children.count > 1

        if isMultiBlock {
            renderMultiBlockListItem(children: children, checkbox: checkbox)
        } else {
            html += "<li>"
            if isTask {
                html += renderCheckbox(checkbox!)
            }
            for child in children {
                visit(child)
            }
            html += "</li>\n"
        }
    }

    // MARK: - Multi-block List Item

    private mutating func renderMultiBlockListItem(
        children: [Markup],
        checkbox: Checkbox?
    ) {
        html += "<li>\n"
        var consumedCheckbox = false

        for child in children {
            if !consumedCheckbox, let checkbox = checkbox {
                if let paragraph = child as? Paragraph {
                    // Prepend checkbox to the first paragraph
                    html += "<p>\(renderCheckbox(checkbox))"
                    descendInto(paragraph)
                    html += "</p>\n"
                    consumedCheckbox = true
                    continue
                }
                // First child is NOT a paragraph — prepend checkbox to the first
                // rendered block's content instead of wrapping in an orphan <p>.
                if !consumedCheckbox {
                    let checkboxHTML = renderCheckbox(checkbox)
                    html += "<span class=\"task-checkbox\">\(checkboxHTML)</span>"
                    consumedCheckbox = true
                }
            }
            visit(child)
        }

        html += "</li>\n"
    }

    private func renderCheckbox(_ checkbox: Checkbox) -> String {
        switch checkbox {
        case .checked:
            return "<input type=\"checkbox\" checked disabled> "
        case .unchecked:
            return "<input type=\"checkbox\" disabled> "
        }
    }

    // MARK: - Table

    mutating func visitTable(_ table: Table) {
        html += "<table>\n"
        tableColumnAlignments = table.columnAlignments
        for child in table.children {
            visit(child)
        }
        tableColumnAlignments = nil
        html += "</table>\n"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) {
        html += "<thead>\n<tr>\n"
        inTableHead = true
        currentTableColumn = 0
        descendInto(tableHead)
        inTableHead = false
        html += "</tr>\n</thead>\n"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) {
        if !tableBody.isEmpty {
            html += "<tbody>\n"
            for child in tableBody.children {
                visit(child)
            }
            html += "</tbody>\n"
        }
    }

    mutating func visitTableRow(_ tableRow: Table.Row) {
        html += "<tr>\n"
        currentTableColumn = 0
        descendInto(tableRow)
        html += "</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) {
        let tag = inTableHead ? "th" : "td"
        var attributes: [String] = []

        // Look up alignment from the parent table's columnAlignments.
        if let alignments = tableColumnAlignments, currentTableColumn < alignments.count,
           let alignment = alignments[currentTableColumn] {
            let value: String
            switch alignment {
            case .left:   value = "left"
            case .center: value = "center"
            case .right:  value = "right"
            }
            if !value.isEmpty {
                attributes.append("style=\"text-align: \(value);\"")
            }
        }
        currentTableColumn += 1

        if tableCell.colspan > 1 {
            attributes.append("colspan=\"\(tableCell.colspan)\"")
        }
        if tableCell.rowspan > 1 {
            attributes.append("rowspan=\"\(tableCell.rowspan)\"")
        }

        let attrStr = attributes.isEmpty ? "" : " " + attributes.joined(separator: " ")
        html += "<\(tag)\(attrStr)>"
        descendInto(tableCell)
        html += "</\(tag)>\n"
    }

    // MARK: - Inline Elements

    mutating func visitText(_ text: Text) {
        html += escapeHTML(text.string)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        html += "<em>"
        descendInto(emphasis)
        html += "</em>"
    }

    mutating func visitStrong(_ strong: Strong) {
        html += "<strong>"
        descendInto(strong)
        html += "</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        html += "<del>"
        descendInto(strikethrough)
        html += "</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        html += "<code>\(escapeHTML(inlineCode.code))</code>"
    }

    mutating func visitLink(_ link: Link) {
        let href = escapeAttribute(link.destination ?? "")
        html += "<a href=\"\(href)\">"
        descendInto(link)
        html += "</a>"
    }

    mutating func visitImage(_ image: Image) {
        let src = escapeAttribute(image.source ?? "")
        let alt = escapeAttribute(image.plainText)
        let title = image.title.map { " title=\"\(escapeAttribute($0))\"" } ?? ""
        html += "<img src=\"\(src)\" alt=\"\(alt)\"\(title)>"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        html += "<br>\n"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        html += "\n"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        html += inlineHTML.rawHTML
    }

    // MARK: - Helpers

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func escapeAttribute(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
